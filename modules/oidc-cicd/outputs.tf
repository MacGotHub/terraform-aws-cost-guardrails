output "plan_role_arn" {
  description = "Read-only role assumable from any ref/PR in this repo."
  value       = aws_iam_role.plan.arn
}

output "plan_role_name" {
  description = "Name of the plan role, for attaching your own aws_iam_role_policy resources."
  value       = aws_iam_role.plan.name
}

output "apply_role_arn" {
  description = "Read-write role assumable only from a push to var.apply_branch."
  value       = aws_iam_role.apply.arn
}

output "apply_role_name" {
  description = "Name of the apply role, for attaching your own aws_iam_role_policy resources."
  value       = aws_iam_role.apply.name
}

output "oidc_provider_arn" {
  description = "The GitHub Actions OIDC provider ARN in use -- either created by this module, or the existing_oidc_provider_arn you passed in."
  value       = local.oidc_provider_arn
}
