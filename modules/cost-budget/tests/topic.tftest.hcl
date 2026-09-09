# Guards the one thing that, if silently flipped back, recreates the
# incident: AWS Budgets can't publish to an alias/aws/sns-encrypted topic,
# so the topic this module creates must be unencrypted by default.

# Realistic SNS ARN so aws_budgets_budget's subscriber_sns_topic_arns
# ARN validation passes under the mock.
mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:unit-budget-alerts"
    }
  }
}

variables {
  name          = "unit"
  monthly_limit = 15
}

run "created_topic_is_unencrypted_by_default" {
  command = plan

  assert {
    condition     = aws_sns_topic.this[0].kms_master_key_id == null
    error_message = "the budget topic must be unencrypted by default -- AWS Budgets can't publish through alias/aws/sns"
  }
}

run "existing_topic_short_circuits_creation" {
  command = plan

  variables {
    create_sns_topic       = false
    existing_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:shared"
  }

  assert {
    condition     = length(aws_sns_topic.this) == 0
    error_message = "create_sns_topic = false should create no topic"
  }
  assert {
    condition     = output.sns_topic_arn == "arn:aws:sns:us-east-1:123456789012:shared"
    error_message = "sns_topic_arn output should be the passed-in existing topic"
  }
}
