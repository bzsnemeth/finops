output "lambda_function_arn" {
  description = "ARN of the anomaly detector Lambda function"
  value       = aws_lambda_function.anomaly_detector.arn
}

output "lambda_function_name" {
  description = "Name of the anomaly detector Lambda function"
  value       = aws_lambda_function.anomaly_detector.function_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost anomaly alerts"
  value       = aws_sns_topic.anomaly_alerts.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.daily.arn
}
