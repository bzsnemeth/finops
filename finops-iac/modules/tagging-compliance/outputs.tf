output "config_rule_arn" {
  description = "ARN of the AWS Config rule for required tags"
  value       = aws_config_config_rule.required_tags.arn
}

output "config_rule_name" {
  description = "Name of the AWS Config rule"
  value       = aws_config_config_rule.required_tags.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for tagging compliance alerts"
  value       = aws_sns_topic.tagging_compliance.arn
}
