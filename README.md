# terraform-aws-cost-guardrails

Small, composable OpenTofu/Terraform modules for the two things every AWS
side project needs and almost none of them have: a secure CI/CD trust
boundary, and a cost budget that actually reaches a human being.

## Why this exists

A personal AWS project's `ais-ingest` task ran unfiltered global data
ingestion for a week. DynamoDB write costs went from $6/day to $38/day
and were still climbing. The account's only budget -- $10/month, alerting
at 85% and 100% -- had **zero notification subscribers**. It had been
alarming into the void the entire time.

That's not a rare mistake. It's the default outcome of copy-pasting a
budget from a tutorial once and never coming back to it. These modules
are the fix, extracted from three real projects that had each
independently rebuilt some version of the same pattern.

## Modules

| Module | Status | What it does |
|---|---|---|
| [`cost-budget`](modules/cost-budget) | Available | A monthly budget with a real, verified SNS subscriber; optional tag filter, optional hard-stop IAM lockout |
| [`oidc-cicd`](modules/oidc-cicd) | Available | GitHub Actions OIDC trust boundary -- read-only plan role, branch-pinned read-write apply role, no static keys |
| [`kill-switch`](modules/kill-switch) | Proposed | SSM-parameter pause flag + alarm-triggered responder that stops the compute directly (ECS desired-count 0, Lambda concurrency 0), covering the always-on ECS/Fargate task the old pattern couldn't. Interface drafted; see the module README's open questions |
| `abuse-alarm` | Planned | Generic log-metric-filter -> CloudWatch alarm -> SNS, for a structured "this looks like abuse, not organic traffic" signal |
| `waf-basic` | Planned | Rate-limited WAF WebACL for CloudFront or API Gateway |

## Gaps this doesn't close yet

A follow-up runaway in the same project (2026-09-07: an `ais-ingest`
Fargate task writing every AIS position report to DynamoDB, each write
fanning out to a full-projection GSI -- ~1M write units/hour, ~$38/day)
sharpened what the planned modules actually need to do:

- **A budget is a slow backstop, not a detector.** The write flood ran for
  days before month-to-date crossed a percentage threshold. A per-resource
  CloudWatch alarm (DynamoDB `ConsumedWriteCapacityUnits` per table, Lambda
  invocations, ECS task count) catches the same event hours in, not days.
  That's `abuse-alarm`'s job -- treat it as the primary signal, with
  `cost-budget` as the money-side safety net behind it.
- **The hard stop has to reach the thing that's actually spending.**
  `cost-budget`'s `hard_stop_role_names` and the original incident's Budget
  Action both only revoke a named Lambda role -- neither could have stopped
  an always-on ECS/Fargate task. `kill-switch` needs a pause path that
  covers a running container (desired-count 0, or an SSM flag the task
  polls), not just a Lambda deny policy.
- **Attribution has to exist before the incident, not after.** The
  `Project` cost-allocation tag wasn't activated until mid-incident, so
  tag-filtered Cost Explorer had no history to diagnose from. `cost-budget`
  exposes `activate_cost_allocation_tag` -- turn it on with the first
  `apply`, not the first surprise.

## Quickstart

```hcl
module "cicd" {
  source  = "app.terraform.io/macgothub/oidc-cicd/aws"
  version = "~> 0.1"

  name_prefix  = "my-project"
  github_owner = "my-github-user"
  github_repo  = "my-project"

  tags = { Project = "my-project" }
}

module "budget" {
  source  = "app.terraform.io/macgothub/cost-budget/aws"
  version = "~> 0.1"

  name                          = "my-project"
  monthly_limit                 = 15
  activate_cost_allocation_tag  = true

  tags = { Project = "my-project" }
}
```

Then subscribe yourself for real:

```bash
aws sns subscribe \
  --topic-arn "$(tofu output -raw budget_alerts_topic_arn)" \
  --protocol email \
  --notification-endpoint you@example.com
```

See [`examples/minimal`](examples/minimal) for a complete working example,
and each module's own README for the full input/output reference and the
design tradeoffs behind it.

## Design principles

- **Least privilege doesn't generalize -- trust boundaries do.**
  `oidc-cicd` ships the OIDC trust policy shape (who can assume what, from
  which branch) and deliberately no permissions. A module that attached a
  generic "reasonable" IAM policy would be a soft AdministratorAccess
  grant in disguise the moment a second project used it.
- **An alert nobody subscribed to isn't an alert.** Every module that
  sends notifications is built around a real, verified subscriber, not
  just a resource that technically has a `notification` block.
- **Automated cost cutoffs are a real availability risk, not a free
  safety net.** The hard-stop option in `cost-budget` is off by default
  and documented as such -- AWS Budget Actions can't distinguish a cost
  spike caused by abuse from one caused by success.

## License

MIT -- see [LICENSE](LICENSE).
