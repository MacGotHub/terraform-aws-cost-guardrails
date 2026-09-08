# Proposed interface for the kill-switch module. No main.tf yet -- see
# README.md's "Open questions" before implementing.

variable "name" {
  description = "Project name, e.g. \"my-project\". Prefixes the SSM parameters, the responder Lambda, the trigger SNS topic, and the EventBridge rule."
  type        = string
}

variable "ecs_services" {
  description = <<-EOT
    ECS services to stop when the switch is armed (desired count -> 0) and
    restore when it's set safe. Each service's pre-arm desired count is
    stashed so restore returns it to where it was, not a guess.
  EOT
  type = list(object({
    cluster = string
    service = string
  }))
  default = []
}

variable "lambda_function_names" {
  description = <<-EOT
    Lambda functions to stop when the switch is armed, by setting reserved
    concurrency to 0 (every invocation then gets a 429). Restore removes
    the reservation. This is blunt -- health-check and retry callers get
    429s too; for a graceful pause, have the function read
    state_parameter_name itself and fail closed instead of listing it here.
  EOT
  type        = list(string)
  default     = []
}

variable "create_trigger_topic" {
  description = "Whether to create the SNS topic that CloudWatch alarms publish to in order to arm the switch. Set false and pass existing_trigger_topic_arn to reuse one topic across projects."
  type        = bool
  default     = true
}

variable "existing_trigger_topic_arn" {
  description = "ARN of an existing SNS topic to subscribe the responder to. Required when create_trigger_topic is false; ignored otherwise."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the responder Lambda's log group."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
