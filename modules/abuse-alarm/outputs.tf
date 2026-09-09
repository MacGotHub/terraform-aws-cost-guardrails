output "sns_topic_arn" {
  description = "The SNS topic alarm notifications go to -- either the one this module created, or the existing_sns_topic_arn you passed in. Subscribe a real endpoint here (see README) and confirm it."
  value       = local.sns_topic_arn
}

output "alarm_arns" {
  description = "Map of alarm key -> alarm ARN."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "Map of alarm key -> full alarm name (\"<name>-<key>\")."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}
