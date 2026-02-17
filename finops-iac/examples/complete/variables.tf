variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_prefix" {
  description = "Prefix for resource naming (e.g., company name)"
  type        = string
}

variable "anomaly_threshold" {
  description = "Cost deviation percentage to trigger anomaly alerts"
  type        = number
  default     = 30
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for cost anomaly alerts"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for SNS alert subscriptions"
  type        = string
}

variable "required_tags" {
  description = "Tag keys to enforce across resources"
  type        = list(string)
  default     = ["Environment", "Team", "CostCenter", "Project"]
}

variable "generate_scp" {
  description = "Generate SCP policy to deny untagged resource creation"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
