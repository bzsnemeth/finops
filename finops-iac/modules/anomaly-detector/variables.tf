variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "anomaly_threshold" {
  description = "Percentage deviation from rolling average to trigger alert"
  type        = number
  default     = 30
}

variable "lookback_days" {
  description = "Number of days for rolling average calculation"
  type        = number
  default     = 7
}

variable "schedule" {
  description = "EventBridge cron/rate schedule for anomaly checks"
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for alerts (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for SNS alert subscription (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
