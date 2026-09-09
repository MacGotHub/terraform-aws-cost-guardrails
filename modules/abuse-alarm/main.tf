# -----------------------------------------------
# Per-resource CloudWatch alarms -> SNS. The detector the 2026-09-07
# incident needed: an account's only cost signal was a monthly AWS Budget,
# which didn't cross its percentage threshold until the runaway had been
# accruing for days. A metric alarm on the resource that's actually
# spending (DynamoDB write units, Lambda invocations, ...) fires in
# minutes. This module is only the detector -- pair it with a human
# response, or a kill-switch, for what happens next.
#
# Same "an alert nobody subscribed to isn't an alert" rule as cost-budget:
# this creates the topic but NOT the email subscription -- an address in
# .tf/state is a leak. Subscribe out of band (see README) and confirm it.
#
# The topic is unencrypted by default: CloudWatch alarms can't publish to
# an alias/aws/sns-encrypted topic (no KMS integration on that path), and
# a silently-undeliverable alarm is the failure this module is meant to
# prevent. See var.sns_kms_key_id for the customer-managed-key path.
# -----------------------------------------------

resource "aws_sns_topic" "this" {
  count = var.create_sns_topic ? 1 : 0

  name              = "${var.name}-abuse-alarms"
  kms_master_key_id = var.sns_kms_key_id

  tags = merge(var.tags, { Name = "${var.name}-abuse-alarms" })
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

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = var.alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = coalesce(each.value.description, "abuse-alarm: ${each.value.namespace} ${each.value.metric_name} over ${each.value.threshold}")
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison_operator
  treat_missing_data  = each.value.treat_missing_data

  alarm_actions = [local.sns_topic_arn]
  ok_actions    = var.notify_on_recovery ? [local.sns_topic_arn] : []

  tags = var.tags
}
