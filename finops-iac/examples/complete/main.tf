####################################
# Complete FinOps Toolkit Deployment
# Wires all three modules together
####################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "my-terraform-state"
  #   key            = "finops-toolkit/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "finops-toolkit"
      ManagedBy = "terraform"
    }
  }
}

# ──────────────────────────────────
# Module 1: CUR Pipeline
# ──────────────────────────────────

module "cur_pipeline" {
  source = "../../modules/cur-pipeline"

  environment          = var.environment
  bucket_name          = "${var.project_prefix}-cur-data"
  athena_database_name = "finops_${var.environment}"
  crawler_schedule     = "cron(0 1 * * ? *)"
  retention_days       = 730

  tags = var.tags
}

# ──────────────────────────────────
# Module 2: Anomaly Detector
# ──────────────────────────────────

module "anomaly_detector" {
  source = "../../modules/anomaly-detector"

  environment       = var.environment
  anomaly_threshold = var.anomaly_threshold
  lookback_days     = 7
  schedule          = "cron(0 8 * * ? *)"
  slack_webhook_url = var.slack_webhook_url
  alert_email       = var.alert_email

  tags = var.tags
}

# ──────────────────────────────────
# Module 3: Tagging Compliance
# ──────────────────────────────────

module "tagging_compliance" {
  source = "../../modules/tagging-compliance"

  environment   = var.environment
  required_tags = var.required_tags
  alert_email   = var.alert_email
  generate_scp  = var.generate_scp

  tags = var.tags
}

# ──────────────────────────────────
# Outputs
# ──────────────────────────────────

output "cur_bucket" {
  value = module.cur_pipeline.cur_bucket_name
}

output "athena_database" {
  value = module.cur_pipeline.athena_database_name
}

output "anomaly_detector_function" {
  value = module.anomaly_detector.lambda_function_name
}

output "anomaly_sns_topic" {
  value = module.anomaly_detector.sns_topic_arn
}

output "tagging_config_rule" {
  value = module.tagging_compliance.config_rule_name
}
