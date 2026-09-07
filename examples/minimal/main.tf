terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------
# Secure CI/CD: OIDC trust boundary, no static AWS keys.
# -----------------------------------------------

module "cicd" {
  source = "../../modules/oidc-cicd"

  name_prefix  = "my-project"
  github_owner = "my-github-user"
  github_repo  = "my-project"

  # First project in the account creates the provider; set to false and
  # pass existing_oidc_provider_arn if another one already exists.
  create_oidc_provider = true

  tags = { Project = "my-project" }
}

# The module intentionally attaches no permissions -- this is the
# minimum viable read policy for a plan step that does nothing but
# confirm which account it's in. Real projects grow this one PR at a
# time as they add resources, exactly like every project this module was
# extracted from does.
resource "aws_iam_role_policy" "plan_read_minimal" {
  name = "my-project-plan-read-minimal"
  role = module.cicd.plan_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "CallerIdentity"
      Effect   = "Allow"
      Action   = "sts:GetCallerIdentity"
      Resource = "*"
    }]
  })
}

# -----------------------------------------------
# Cost guardrail: a real budget with a real subscriber.
# -----------------------------------------------

module "budget" {
  source = "../../modules/cost-budget"

  name                         = "my-project"
  monthly_limit                = 15
  activate_cost_allocation_tag = true

  tags = { Project = "my-project" }
}

output "plan_role_arn" {
  value = module.cicd.plan_role_arn
}

output "apply_role_arn" {
  value = module.cicd.apply_role_arn
}

output "budget_alerts_topic_arn" {
  description = "Subscribe an email with: aws sns subscribe --topic-arn <this> --protocol email --notification-endpoint you@example.com"
  value       = module.budget.sns_topic_arn
}
