variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "bucket_name" {
  description = "S3 bucket name for CUR data storage"
  type        = string
}

variable "athena_database_name" {
  description = "Name for the Glue/Athena database"
  type        = string
  default     = "finops_cur"
}

variable "cur_report_prefix" {
  description = "S3 prefix where CUR reports are delivered"
  type        = string
  default     = "cur-reports"
}

variable "crawler_schedule" {
  description = "Cron schedule for Glue Crawler (e.g., 'cron(0 1 * * ? *)')"
  type        = string
  default     = "cron(0 1 * * ? *)"
}

variable "retention_days" {
  description = "Number of days to retain CUR data before expiration"
  type        = number
  default     = 730
}

variable "force_destroy" {
  description = "Allow destruction of S3 buckets with objects"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
