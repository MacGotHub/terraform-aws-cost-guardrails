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
| [`abuse-alarm`](modules/abuse-alarm) | Available | Per-resource CloudWatch metric alarms -> SNS -- the fast detector a monthly budget isn't. Fires in minutes on a DynamoDB write spike, Lambda invocation flood, etc. |
| `kill-switch` | Deferred | Alarm/manual → stop the compute directly (ECS desired-count 0, Lambda concurrency 0) — covers the always-on ECS/Fargate task the budget hard-stop can't. Design drafted on the `propose-kill-switch-module` branch; deferred because automated hard-stop is a real availability risk and `abuse-alarm` + a human is most of the value |
| `waf-basic` | Planned | Rate-limited WAF WebACL for CloudFront or API Gateway |

## The 2026-09-07 follow-up incident, and what it changed

A second runaway in the same project (an `ais-ingest` Fargate task writing
every AIS position report to DynamoDB, each write fanning out to a
full-projection GSI -- ~1M write units/hour, ~$38/day) sharpened three
things:

- **A budget is a slow backstop, not a detector.** The write flood ran for
  days before month-to-date crossed a percentage threshold. *Addressed:*
  `abuse-alarm` puts a per-resource CloudWatch alarm on the thing that's
  actually spending -- treat it as the primary signal, with `cost-budget`
  as the money-side net behind it.
- **Attribution has to exist before the incident, not after.** The
  `Project` cost-allocation tag wasn't activated until mid-incident, so
  tag-filtered Cost Explorer had no history to diagnose from. *Addressed:*
  `cost-budget`'s `activate_cost_allocation_tag` -- turn it on with the
  first `apply`, not the first surprise.
- **The hard stop has to reach the thing that's actually spending** --
  still open. `cost-budget`'s `hard_stop_role_names` and a Budget Action
  both only revoke a named Lambda role; neither stops an always-on
  ECS/Fargate task. That's `kill-switch`'s job, and it's deferred:
  automated hard-stop is a real availability risk for these projects, and
  `abuse-alarm` paging a human who runs one command is most of the value.

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
