variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "required_tags" {
  description = "List of tag keys that must be present on resources (max 6)"
  type        = list(string)
  default     = ["Environment", "Team", "CostCenter", "Project"]

  validation {
    condition     = length(var.required_tags) <= 6
    error_message = "AWS Config REQUIRED_TAGS supports a maximum of 6 tag keys."
  }
}

variable "alert_email" {
  description = "Email address for compliance alert subscription (optional)"
  type        = string
  default     = ""
}

variable "generate_scp" {
  description = "Generate an SCP policy file to deny untagged resource creation"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
