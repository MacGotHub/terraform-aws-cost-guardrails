variable "name" {
  description = "Project/budget name, e.g. \"my-project\". Used for the budget's own name and, when tag_filter_key is set, as the tag value to filter cost by."
  type        = string
}

variable "monthly_limit" {
  description = "Monthly budget limit in USD."
  type        = number
}

variable "tag_filter_key" {
  description = "Cost-allocation tag key to filter this budget by, e.g. \"Project\". Set to null for an account-wide budget with no filter. The tag must be activated as a user-defined cost allocation tag in Billing preferences or actual spend will silently report as $0 -- see activate_cost_allocation_tag."
  type        = string
  default     = "Project"
}

variable "activate_cost_allocation_tag" {
  description = "Whether this module should activate var.tag_filter_key as a cost allocation tag. Activation is account-wide, not per-budget -- if you have (or will have) more than one cost-budget module instance using the same tag_filter_key, set this true on exactly one of them and false on the rest, or the two will fight over the same account-level setting."
  type        = bool
  default     = false
}

variable "notification_thresholds" {
  description = "Percentages of actual spend at which to notify."
  type        = list(number)
  default     = [80, 100]
}

variable "forecasted_threshold" {
  description = "Percentage of forecasted spend at which to notify, or null to skip the forecast notification."
  type        = number
  default     = 100
}

variable "create_sns_topic" {
  description = "Whether to create a dedicated SNS topic for this budget. Set false and pass existing_sns_topic_arn to share one topic across multiple cost-budget instances."
  type        = bool
  default     = true
}

variable "existing_sns_topic_arn" {
  description = "SNS topic ARN to notify. Required when create_sns_topic is false; ignored otherwise."
  type        = string
  default     = null
}

variable "sns_kms_key_id" {
  description = <<-EOT
    KMS key for the SNS topic this module creates. Default is null
    (unencrypted) on purpose: AWS Budgets cannot publish to a topic
    encrypted with the AWS-managed key (alias/aws/sns) -- the notification
    is silently dropped, which is the exact "alerts into the void" failure
    this module exists to prevent. (Same limitation hits CloudWatch alarm
    actions; confirmed live -- see the abuse-alarm module's notes.)

    To encrypt, pass a *customer-managed* key whose policy already grants
    budgets.amazonaws.com kms:Decrypt and kms:GenerateDataKey*. Budget
    notifications ("you're at 80% of $15") aren't sensitive, so
    unencrypted is a reasonable default.
  EOT
  type        = string
  default     = null
}

variable "enable_hard_stop" {
  description = <<-EOT
    Whether to attach an AWS Budget Action that applies a deny-all IAM
    policy to hard_stop_role_names once actual spend hits 100%.

    This is a blunt, automated cutoff. It's appropriate for a cost-bearing
    role fronting public/unauthenticated traffic (a paid API, an ingestion
    task) where a runaway bill is a bigger risk than a false-positive
    outage. It's a real availability risk if applied to a role your own
    deploy pipeline, or a paying customer's traffic, depends on -- AWS
    Budget Actions can't distinguish "this spike is abuse" from "this
    spike is a product launch going well." Off by default.
  EOT
  type        = bool
  default     = false
}

variable "hard_stop_role_names" {
  description = "IAM role names to deny-all when the hard stop fires. Required (non-empty) when enable_hard_stop is true."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
