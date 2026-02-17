####################################
# Cost Anomaly Detector Module
# Lambda + EventBridge + SNS/Slack
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
  name_prefix   = "finops-${var.environment}"
  function_name = "${local.name_prefix}-anomaly-detector"
  tags = merge(var.tags, {
    Module      = "anomaly-detector"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ──────────────────────────────────
# SNS Topic for Alerts
# ──────────────────────────────────

resource "aws_sns_topic" "anomaly_alerts" {
  name = "${local.name_prefix}-cost-anomaly-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.anomaly_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ──────────────────────────────────
# Lambda Function
# ──────────────────────────────────

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/handler.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${local.function_name}-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CostExplorerAccess"
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = aws_sns_topic.anomaly_alerts.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "anomaly_detector" {
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  function_name    = local.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      ANOMALY_THRESHOLD = tostring(var.anomaly_threshold)
      LOOKBACK_DAYS     = tostring(var.lookback_days)
      SNS_TOPIC_ARN     = aws_sns_topic.anomaly_alerts.arn
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      ENVIRONMENT       = var.environment
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30
  tags              = local.tags
}

# ──────────────────────────────────
# EventBridge Schedule (daily trigger)
# ──────────────────────────────────

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${local.name_prefix}-daily-anomaly-check"
  description         = "Triggers cost anomaly detection daily"
  schedule_expression = var.schedule
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.daily.name
  target_id = "anomaly-detector-lambda"
  arn       = aws_lambda_function.anomaly_detector.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anomaly_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}
