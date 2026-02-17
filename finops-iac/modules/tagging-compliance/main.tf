####################################
# Tagging Compliance Module
# AWS Config Rules + SNS Alerting
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
    Module      = "tagging-compliance"
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # Resource types to monitor for tagging compliance
  resource_types = [
    "AWS::EC2::Instance",
    "AWS::EC2::Volume",
    "AWS::RDS::DBInstance",
    "AWS::S3::Bucket",
    "AWS::Lambda::Function",
    "AWS::ECS::Cluster",
    "AWS::EKS::Cluster",
    "AWS::ElasticLoadBalancingV2::LoadBalancer",
  ]
}

# ──────────────────────────────────
# SNS Topic for Compliance Alerts
# ──────────────────────────────────

resource "aws_sns_topic" "tagging_compliance" {
  name = "${local.name_prefix}-tagging-compliance"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.tagging_compliance.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ──────────────────────────────────
# AWS Config Rule: required-tags
# ──────────────────────────────────

resource "aws_config_config_rule" "required_tags" {
  name        = "${local.name_prefix}-required-tags"
  description = "Checks that required FinOps tags are present on monitored resources"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = try(var.required_tags[0], null)
    tag2Key = try(var.required_tags[1], null)
    tag3Key = try(var.required_tags[2], null)
    tag4Key = try(var.required_tags[3], null)
    tag5Key = try(var.required_tags[4], null)
    tag6Key = try(var.required_tags[5], null)
  })

  scope {
    compliance_resource_types = local.resource_types
  }

  tags = local.tags
}

# ──────────────────────────────────
# EventBridge Rule for Compliance Changes
# ──────────────────────────────────

resource "aws_cloudwatch_event_rule" "compliance_change" {
  name        = "${local.name_prefix}-tag-compliance-change"
  description = "Fires when AWS Config compliance status changes for tagging rules"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      configRuleName  = [aws_config_config_rule.required_tags.name]
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.compliance_change.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.tagging_compliance.arn

  input_transformer {
    input_paths = {
      resource = "$.detail.resourceId"
      rule     = "$.detail.configRuleName"
      type     = "$.detail.resourceType"
      account  = "$.detail.awsAccountId"
      region   = "$.detail.awsRegion"
    }
    input_template = <<-TEMPLATE
      "🏷️ Tagging Non-Compliance Detected\n\nResource: <resource>\nType: <type>\nRule: <rule>\nAccount: <account>\nRegion: <region>\n\nAction Required: Add missing required tags to this resource."
    TEMPLATE
  }
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.tagging_compliance.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.tagging_compliance.arn
      }
    ]
  })
}

# ──────────────────────────────────
# SCP: Deny Untagged Resource Creation (optional)
# ──────────────────────────────────

resource "local_file" "scp_policy" {
  count    = var.generate_scp ? 1 : 0
  filename = "${path.module}/generated-scp.json"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUntaggedEC2"
        Effect    = "Deny"
        Action    = ["ec2:RunInstances"]
        Resource  = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:volume/*"]
        Condition = {
          "Null" = {
            for tag in var.required_tags : "aws:RequestTag/${tag}" => "true"
          }
        }
      },
      {
        Sid       = "DenyUntaggedRDS"
        Effect    = "Deny"
        Action    = ["rds:CreateDBInstance"]
        Resource  = ["*"]
        Condition = {
          "Null" = {
            for tag in var.required_tags : "aws:RequestTag/${tag}" => "true"
          }
        }
      }
    ]
  })
}
