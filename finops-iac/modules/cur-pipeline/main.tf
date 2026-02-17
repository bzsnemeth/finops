####################################
# CUR Pipeline Module
# CUR Export → S3 → Glue Crawler → Athena
####################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  name_prefix = "finops-${var.environment}"
  tags = merge(var.tags, {
    Module      = "cur-pipeline"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ──────────────────────────────────
# S3 Bucket for CUR Data
# ──────────────────────────────────

resource "aws_s3_bucket" "cur" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "cur" {
  bucket = aws_s3_bucket.cur.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket                  = aws_s3_bucket.cur.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    expiration {
      days = var.retention_days
    }
  }
}

# S3 bucket policy for CUR delivery
resource "aws_s3_bucket_policy" "cur" {
  bucket = aws_s3_bucket.cur.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCURDelivery"
        Effect    = "Allow"
        Principal = { Service = "billingreports.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:GetBucketPolicy"]
        Resource  = aws_s3_bucket.cur.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "aws:SourceArn"     = "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
          }
        }
      },
      {
        Sid       = "AllowCURWrite"
        Effect    = "Allow"
        Principal = { Service = "billingreports.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cur.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "aws:SourceArn"     = "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
          }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ──────────────────────────────────
# Glue Catalog Database
# ──────────────────────────────────

resource "aws_glue_catalog_database" "cur" {
  name = var.athena_database_name

  create_table_default_permission {
    permissions = ["ALL"]
    principal {
      data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS"
    }
  }

  tags = local.tags
}

# ──────────────────────────────────
# Glue Crawler (populates Athena tables from CUR Parquet)
# ──────────────────────────────────

resource "aws_iam_role" "glue_crawler" {
  name = "${local.name_prefix}-cur-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "glue_crawler" {
  name = "${local.name_prefix}-cur-crawler-policy"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cur.arn,
          "${aws_s3_bucket.cur.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:*Database*",
          "glue:*Table*",
          "glue:*Partition*",
          "glue:BatchCreatePartition",
          "glue:BatchGetPartition"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["arn:aws:logs:*:*:*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_glue_crawler" "cur" {
  name          = "${local.name_prefix}-cur-crawler"
  role          = aws_iam_role.glue_crawler.arn
  database_name = aws_glue_catalog_database.cur.name
  description   = "Crawls CUR Parquet data to populate Athena tables"

  s3_target {
    path = "s3://${aws_s3_bucket.cur.id}/${var.cur_report_prefix}/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "DELETE_FROM_DATABASE"
  }

  schedule = var.crawler_schedule

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })

  tags = local.tags
}

# ──────────────────────────────────
# Athena Workgroup
# ──────────────────────────────────

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.bucket_name}-athena-results"
  force_destroy = var.force_destroy
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_athena_workgroup" "finops" {
  name  = "${local.name_prefix}-workgroup"
  state = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = local.tags
}

# ──────────────────────────────────
# Athena Named Queries (pre-built FinOps queries)
# ──────────────────────────────────

resource "aws_athena_named_query" "daily_spend" {
  name        = "daily-spend-by-service"
  workgroup   = aws_athena_workgroup.finops.name
  database    = aws_glue_catalog_database.cur.name
  description = "Daily spend breakdown by AWS service"

  query = <<-SQL
    SELECT
      line_item_usage_start_date AS usage_date,
      line_item_product_code AS service,
      SUM(line_item_unblended_cost) AS daily_cost,
      SUM(line_item_usage_amount) AS usage_amount
    FROM "${aws_glue_catalog_database.cur.name}"."cur"
    WHERE line_item_line_item_type = 'Usage'
      AND year = CAST(YEAR(CURRENT_DATE) AS VARCHAR)
      AND month = LPAD(CAST(MONTH(CURRENT_DATE) AS VARCHAR), 2, '0')
    GROUP BY 1, 2
    ORDER BY 1 DESC, 3 DESC
  SQL
}

resource "aws_athena_named_query" "team_allocation" {
  name        = "cost-by-team"
  workgroup   = aws_athena_workgroup.finops.name
  database    = aws_glue_catalog_database.cur.name
  description = "Monthly cost allocation by team tag"

  query = <<-SQL
    SELECT
      resource_tags_user_team AS team,
      line_item_product_code AS service,
      SUM(line_item_unblended_cost) AS total_cost,
      COUNT(DISTINCT line_item_resource_id) AS resource_count
    FROM "${aws_glue_catalog_database.cur.name}"."cur"
    WHERE line_item_line_item_type = 'Usage'
      AND year = CAST(YEAR(CURRENT_DATE) AS VARCHAR)
      AND month = LPAD(CAST(MONTH(CURRENT_DATE) AS VARCHAR), 2, '0')
    GROUP BY 1, 2
    ORDER BY 3 DESC
  SQL
}

resource "aws_athena_named_query" "untagged_spend" {
  name        = "untagged-resource-spend"
  workgroup   = aws_athena_workgroup.finops.name
  database    = aws_glue_catalog_database.cur.name
  description = "Spend on resources missing required tags"

  query = <<-SQL
    SELECT
      line_item_product_code AS service,
      line_item_resource_id AS resource_id,
      SUM(line_item_unblended_cost) AS untagged_cost
    FROM "${aws_glue_catalog_database.cur.name}"."cur"
    WHERE line_item_line_item_type = 'Usage'
      AND (resource_tags_user_team IS NULL OR resource_tags_user_team = '')
      AND line_item_unblended_cost > 0
      AND year = CAST(YEAR(CURRENT_DATE) AS VARCHAR)
      AND month = LPAD(CAST(MONTH(CURRENT_DATE) AS VARCHAR), 2, '0')
    GROUP BY 1, 2
    ORDER BY 3 DESC
    LIMIT 50
  SQL
}

resource "aws_athena_named_query" "ri_sp_coverage" {
  name        = "savings-plan-ri-coverage"
  workgroup   = aws_athena_workgroup.finops.name
  database    = aws_glue_catalog_database.cur.name
  description = "Savings Plan and Reserved Instance coverage analysis"

  query = <<-SQL
    SELECT
      DATE_TRUNC('day', line_item_usage_start_date) AS usage_date,
      SUM(CASE WHEN line_item_line_item_type = 'SavingsPlanCoveredUsage' THEN line_item_unblended_cost ELSE 0 END) AS sp_covered_cost,
      SUM(CASE WHEN line_item_line_item_type = 'DiscountedUsage' THEN line_item_unblended_cost ELSE 0 END) AS ri_covered_cost,
      SUM(CASE WHEN line_item_line_item_type = 'Usage' THEN line_item_unblended_cost ELSE 0 END) AS on_demand_cost,
      SUM(line_item_unblended_cost) AS total_cost
    FROM "${aws_glue_catalog_database.cur.name}"."cur"
    WHERE year = CAST(YEAR(CURRENT_DATE) AS VARCHAR)
      AND month = LPAD(CAST(MONTH(CURRENT_DATE) AS VARCHAR), 2, '0')
    GROUP BY 1
    ORDER BY 1
  SQL
}
