# abuse-alarm

Per-resource CloudWatch alarms wired to a real, verified SNS subscriber.
The fast detector that a monthly budget isn't.

## Why this exists

The 2026-09-07 incident: an `ais-ingest` task started writing unfiltered
global data to DynamoDB. Writes went from ~$0.08/day to ~$38/day. The
account's only cost signal was a monthly AWS Budget alarming at 85% and
100% -- and month-to-date didn't cross either line until the runaway had
been accruing for **days**.

A budget is a slow, money-side backstop. `abuse-alarm` watches the
resource that's actually spending -- DynamoDB `ConsumedWriteCapacityUnits`,
Lambda `Invocations`, ECS running task count, a 5xx rate -- and fires in
minutes. Treat it as the primary signal; keep `cost-budget` behind it.

**This module only detects.** What happens next -- you get paged and run a
command, or an automated `kill-switch` trips -- is a separate concern.

## Usage

```hcl
module "abuse_alarm" {
  source  = "app.terraform.io/macgothub/abuse-alarm/aws"
  version = "~> 0.4.0"

  name = "my-project"

  alarms = {
    # Only metric_name + threshold are required; the rest default to
    # "Sum over 5 minutes, alarm on the first breach".
    ddb-write-runaway = {
      namespace   = "AWS/DynamoDB"
      metric_name = "ConsumedWriteCapacityUnits"
      dimensions  = { TableName = "my-project-events" }
      # Set from a known-good baseline. ~4 writes/sec steady -> ~1200/5min;
      # 20000 is "roughly 15x normal", i.e. something is wrong.
      threshold = 20000
    }

    voice-lambda-flood = {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      dimensions  = { FunctionName = "my-project-voice" }
      period      = 60
      threshold   = 300
    }
  }

  tags = { Project = "my-project" }
}
```

Then subscribe an endpoint out of band -- never in your `.tf`/state:

```bash
aws sns subscribe \
  --topic-arn "$(tofu output -raw abuse_alarm_topic_arn)" \
  --protocol email \
  --notification-endpoint you@example.com
# ...then click the confirmation link. An unconfirmed subscription is not
# a subscriber -- same failure mode as the incident above.
```

To share one topic with `cost-budget` instead of creating a second:

```hcl
module "abuse_alarm" {
  # ...
  create_sns_topic       = false
  existing_sns_topic_arn = module.budget.sns_topic_arn
}
```

## Scope

- **Single-metric static-threshold alarms only.** Composite alarms,
  metric-math, and anomaly-detection bands are deliberately out -- add a
  plain `aws_cloudwatch_metric_alarm` in your own config for those.
- Set thresholds from a real baseline, not a guess. "Roughly N times
  normal" is the right instinct; a threshold you can't justify from a
  known-good measurement will either miss the runaway or page you at 3am
  for a traffic bump.
- `notify_on_recovery` (default on) also pings you when an alarm clears --
  useful for confirming a fix landed.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Prefix for alarms + the SNS topic | -- |
| `alarms` | Map of key -> alarm spec (`metric_name`, `threshold` required; `namespace`, `dimensions`, `statistic`, `period`, `evaluation_periods`, `datapoints_to_alarm`, `comparison_operator`, `treat_missing_data`, `description` optional) | `{}` |
| `notify_on_recovery` | Also notify on alarm -> OK | `true` |
| `create_sns_topic` | Create a dedicated topic | `true` |
| `existing_sns_topic_arn` | Topic to reuse when `create_sns_topic = false` | `null` |
| `sns_kms_key_id` | KMS key for the created topic | `"alias/aws/sns"` |
| `tags` | Tags for created resources | `{}` |

## Outputs

| Name | Description |
|---|---|
| `sns_topic_arn` | Topic in use -- subscribe a real endpoint here |
| `alarm_arns` | Map of key -> alarm ARN |
| `alarm_names` | Map of key -> full alarm name |
