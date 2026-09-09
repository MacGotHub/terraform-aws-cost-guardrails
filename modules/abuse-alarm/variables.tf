variable "name" {
  description = "Prefix for the alarms and the SNS topic this module creates, e.g. \"my-project\"."
  type        = string
}

variable "alarms" {
  description = <<-EOT
    The alarms to create, keyed by a short name (the full alarm name is
    "<var.name>-<key>"). Each entry is a single-metric CloudWatch alarm --
    the point is early, per-resource detection of a spike (DynamoDB write
    units, Lambda invocations, ECS task count, 4xx/5xx rate, ...), so it
    fires in minutes rather than waiting days for a monthly budget
    threshold to be crossed.

    `namespace`, `metric_name`, and `threshold` are required per entry (no
    default namespace -- a wrong-but-plausible one produces an alarm that
    silently never fires). The rest default to a "sum over 5 minutes,
    alarm on the first breach" shape. Composite alarms and metric-math are
    out of scope here -- add a separate aws_cloudwatch_metric_alarm in
    your own config for those.
  EOT
  type = map(object({
    namespace           = string
    metric_name         = string
    dimensions          = optional(map(string), {})
    statistic           = optional(string, "Sum")
    period              = optional(number, 300)
    evaluation_periods  = optional(number, 1)
    datapoints_to_alarm = optional(number)
    threshold           = number
    comparison_operator = optional(string, "GreaterThanThreshold")
    treat_missing_data  = optional(string, "notBreaching")
    description         = optional(string)
  }))
  default = {}
}

variable "notify_on_recovery" {
  description = "Also send a notification when an alarm returns to OK -- useful for \"it stopped climbing\". Applies to every alarm."
  type        = bool
  default     = true
}

variable "create_sns_topic" {
  description = "Whether to create a dedicated SNS topic for these alarms. Set false and pass existing_sns_topic_arn to route into a topic another guardrail module already owns (e.g. cost-budget's)."
  type        = bool
  default     = true
}

variable "existing_sns_topic_arn" {
  description = "SNS topic ARN to send alarm notifications to. Required when create_sns_topic is false; ignored otherwise."
  type        = string
  default     = null
}

variable "sns_kms_key_id" {
  description = <<-EOT
    KMS key for the SNS topic this module creates. Default is null
    (unencrypted) on purpose: CloudWatch alarms CANNOT publish to a topic
    encrypted with the AWS-managed key (alias/aws/sns) -- the alarm fires,
    the publish is rejected, and no notification goes out. That's the
    exact failure this module exists to catch.

    To encrypt, pass a *customer-managed* key whose policy already grants
    cloudwatch.amazonaws.com kms:Decrypt and kms:GenerateDataKey*. Alarm
    payloads ("metric X is over threshold Y") aren't sensitive, so
    unencrypted is a reasonable default here.
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
