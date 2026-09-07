output "budget_name" {
  value = aws_budgets_budget.this.name
}

output "budget_arn" {
  value = aws_budgets_budget.this.arn
}

output "sns_topic_arn" {
  description = "The SNS topic notifications go to -- either the one this module created, or the existing_sns_topic_arn you passed in."
  value       = local.sns_topic_arn
}
