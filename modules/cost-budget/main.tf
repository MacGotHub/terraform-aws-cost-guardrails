data "aws_caller_identity" "current" {}

# -----------------------------------------------
# SNS topic. Built after a real incident where an account's only budget
# had zero notification subscribers -- its 85/100% alerts had been firing
# into the void the entire time a runaway cost was accruing. A budget with
# nowhere to send its alerts is worse than no budget at all: it looks like
# coverage that doesn't exist.
# -----------------------------------------------

resource "aws_sns_topic" "this" {
  count = var.create_sns_topic ? 1 : 0

  name              = "${var.name}-budget-alerts"
  kms_master_key_id = var.sns_kms_key_id

  tags = merge(var.tags, { Name = "${var.name}-budget-alerts" })
}

locals {
  sns_topic_arn = var.create_sns_topic ? aws_sns_topic.this[0].arn : var.existing_sns_topic_arn
}

check "sns_topic_configured" {
  assert {
    condition     = var.create_sns_topic || var.existing_sns_topic_arn != null
    error_message = "existing_sns_topic_arn is required when create_sns_topic is false."
  }
}

check "hard_stop_roles_configured" {
  assert {
    condition     = !var.enable_hard_stop || length(var.hard_stop_role_names) > 0
    error_message = "hard_stop_role_names must be non-empty when enable_hard_stop is true."
  }
}

# -----------------------------------------------
# Activates the cost-allocation tag this budget filters by. Without this,
# a tag-based budget filter silently reports $0 actual spend forever --
# not an error, just a budget that looks like it's working and isn't.
# Account-wide setting, so only activate it from one module instance if
# you have several sharing the same tag_filter_key.
# -----------------------------------------------

resource "aws_ce_cost_allocation_tag" "this" {
  count = var.activate_cost_allocation_tag && var.tag_filter_key != null ? 1 : 0

  tag_key = var.tag_filter_key
  status  = "Active"
}

resource "aws_budgets_budget" "this" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_limit)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "cost_filter" {
    for_each = var.tag_filter_key == null ? [] : [1]
    content {
      name = "TagKeyValue"
      # format(), not "user:${var.tag_filter_key}$${var.name}" -- HCL reads
      # a literal `$` immediately followed by `{` as the escape for a
      # literal `${`, which would emit the text "var.name" verbatim
      # instead of interpolating it.
      values = [format("user:%s$%s", var.tag_filter_key, var.name)]
    }
  }

  dynamic "notification" {
    for_each = var.notification_thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [local.sns_topic_arn]
    }
  }

  dynamic "notification" {
    for_each = var.forecasted_threshold == null ? [] : [var.forecasted_threshold]
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "FORECASTED"
      subscriber_sns_topic_arns = [local.sns_topic_arn]
    }
  }

  depends_on = [aws_ce_cost_allocation_tag.this]
}

# -----------------------------------------------
# Optional hard stop -- see the enable_hard_stop variable description for
# when this is (and isn't) the right call.
# -----------------------------------------------

resource "aws_iam_policy" "deny_all" {
  count = var.enable_hard_stop ? 1 : 0
  name  = "${var.name}-budget-deny-all"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyAllExceptLogs"
      Effect    = "Deny"
      NotAction = ["logs:*"]
      Resource  = "*"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role" "budgets_action" {
  count = var.enable_hard_stop ? 1 : 0
  name  = "${var.name}-budgets-action"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "budgets_action_attach" {
  count = var.enable_hard_stop ? 1 : 0
  name  = "${var.name}-budgets-action-attach"
  role  = aws_iam_role.budgets_action[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
      Resource = [
        for name in var.hard_stop_role_names :
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}"
      ]
    }]
  })
}

resource "aws_budgets_budget_action" "hard_stop" {
  count = var.enable_hard_stop ? 1 : 0

  budget_name        = aws_budgets_budget.this.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_action[0].arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.deny_all[0].arn
      roles      = var.hard_stop_role_names
    }
  }

  subscriber {
    subscription_type = "SNS"
    address           = local.sns_topic_arn
  }
}
