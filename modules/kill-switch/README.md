# kill-switch

> **Status: design proposal.** This directory has a proposed interface
> (`variables.tf`) and this rationale, but no `main.tf` yet. Open
> questions are at the bottom — resolve those, then implement.

A blunt, fast "stop everything for this project" that works whether the
runaway is driven by Lambda invocations **or** an always-on ECS/Fargate
task.

## Why this exists

The 2026-09-07 incident had a budget hard-stop wired to it. It revoked a
named Lambda role — and the cost was an ECS task writing to DynamoDB, which
that revocation did nothing to. The stop has to reach the thing that's
actually spending, and "the thing" isn't always a Lambda.

`cost-budget`'s `hard_stop` and the classic budget-action pattern both stop
at "detach a policy from a role." `kill-switch` stops the compute directly:
ECS desired count to 0, Lambda reserved concurrency to 0. Unambiguous, and
it covers the case the old pattern couldn't.

## Shape

```
CloudWatch alarm (abuse-alarm, a DynamoDB write-rate alarm, a budget
    action's notification, ...)
    │  alarm_actions ──▶ SNS  (module output: trigger_topic_arn)
    ▼
responder Lambda ──sets──▶ SSM Parameter  /<name>/kill-switch = "armed"
    ▲                                         │
    │  EventBridge rule on Parameter Store    │  (also flips on a manual
    │  Change re-invokes the responder ◀──────┘   `aws ssm put-parameter`)
    ▼
reconcile reality to the flag:
  armed → ecs:UpdateService --desired-count 0 ; lambda:PutFunctionConcurrency 0
  safe  → restore both
```

- **The SSM parameter is the single source of truth.** An operator
  mid-incident can `aws ssm put-parameter --name /<name>/kill-switch
  --value armed --overwrite` and the EventBridge rule does the rest — no
  need to find the Lambda or the alarm.
- **The responder is idempotent.** The alarm path and the manual path both
  converge on "flag is armed, reconcile" — running it twice is a no-op.
- **`safe` is only ever set by a human** (or a deliberate `tofu apply`).
  No auto-resume — same reasoning as `cost-budget`'s hard-stop being
  off by default: you don't want an automated system deciding the
  incident is over.

## Usage (proposed)

```hcl
module "kill_switch" {
  source  = "app.terraform.io/macgothub/kill-switch/aws"
  version = "~> 0.3"

  name = "my-project"

  ecs_services = [
    { cluster = "my-project-ingest", service = "my-project-ingest" },
  ]
  lambda_function_names = [
    aws_lambda_function.expensive_worker.function_name,
  ]

  tags = { Project = "my-project" }
}

# Point your detector at it:
resource "aws_cloudwatch_metric_alarm" "ddb_write_runaway" {
  # ... a threshold on AWS/DynamoDB ConsumedWriteCapacityUnits ...
  alarm_actions = [module.kill_switch.trigger_topic_arn]
}
```

Apps that want a *graceful* pause instead of a blunt 429 / task kill can
read the flag themselves at the top of a handler and fail closed:

```python
if ssm.get_parameter(Name=KILL_SWITCH_PARAM)["Parameter"]["Value"] == "armed":
    raise RuntimeError("kill-switch armed")
```

The module exposes the parameter name (`state_parameter_name`); the
fail-closed logic is yours to add, the same way `oidc-cicd` ships the
trust boundary and leaves the permissions to you.

## What this deliberately does not do

- **Revoke IAM.** Indirect, and the thing the broken pattern did.
- **Auto-resume.** `safe` is a human decision.
- **Cover every compute type.** Lambda functions and ECS services are what
  these projects run. Not EC2 ASGs, Batch, App Runner — add later if a
  project actually needs it.
- **Detect anything.** That's `abuse-alarm` / a plain CloudWatch alarm.
  This module is only the actuator.

## Inputs

See `variables.tf`. Summary: `name`, `ecs_services`,
`lambda_function_names`, the `create_trigger_topic` /
`existing_trigger_topic_arn` share-a-topic pair (same as `cost-budget`),
`log_retention_days`, `tags`.

## Outputs (proposed)

| Name | Description |
|---|---|
| `state_parameter_name` | SSM parameter apps read for a cooperative check |
| `trigger_topic_arn` | Point CloudWatch alarm `alarm_actions` here |
| `responder_function_name` / `_arn` | The reconcile Lambda |

## Open questions — resolve before implementing

1. **ECS restore semantics.** Stash the pre-arm `desiredCount` in a second
   SSM param and restore to it, or restore to a static
   `restore_desired_count` per service (simpler, but wrong if the service
   was scaled)? Leaning: stash — one extra param write per arm is cheap.
2. **Lambda hard stop.** Reserved-concurrency-0 429s *every* caller
   (health checks included). Keep it as the default action, or make
   concurrency-0 opt-in per function and rely on the cooperative SSM check
   otherwise?
3. **Merge with `abuse-alarm`?** They're a natural pair (alarm → arm).
   Separate keeps each composable; combined is what a project always
   actually wants. Leaning: separate, with `abuse-alarm`'s README showing
   the two wired together.
4. **Responder code packaging.** Inline Python via `archive_file` from a
   `modules/kill-switch/src/` dir (self-contained, but this repo has
   shipped only config so far), or a committed prebuilt zip? Leaning:
   inline `src/` — a ~60-line boto3 handler, no deps.
