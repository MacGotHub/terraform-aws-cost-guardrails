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
| `kill-switch` | Planned | SSM-parameter pause flag + alarm-triggered responder, generalized beyond Lambda-only (the gap that let the incident above happen for as long as it did -- the existing pattern didn't cover an always-on ECS/Fargate task) |
| `abuse-alarm` | Planned | Generic log-metric-filter -> CloudWatch alarm -> SNS, for a structured "this looks like abuse, not organic traffic" signal |
| `waf-basic` | Planned | Rate-limited WAF WebACL for CloudFront or API Gateway |

## Quickstart

```hcl
module "cicd" {
  source = "github.com/MacGotHub/terraform-aws-cost-guardrails//modules/oidc-cicd"

  name_prefix  = "my-project"
  github_owner = "my-github-user"
  github_repo  = "my-project"

  tags = { Project = "my-project" }
}

module "budget" {
  source = "github.com/MacGotHub/terraform-aws-cost-guardrails//modules/cost-budget"

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
