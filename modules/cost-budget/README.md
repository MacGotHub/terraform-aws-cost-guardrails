# cost-budget

A monthly AWS Budget wired to a real SNS subscriber, with an optional
tag filter and an optional hard-stop IAM lockout. Built after an incident
where an account's only budget had **zero notification subscribers** --
its alerts had been firing into the void for over a week while a runaway
cost accrued.

## Usage

Account-wide:

```hcl
module "account_budget" {
  source  = "app.terraform.io/macgothub/cost-budget/aws"
  version = "~> 0.1"

  name           = "account"
  monthly_limit  = 30
  tag_filter_key = null # no filter = watches the whole account

  tags = { ManagedBy = "opentofu" }
}
```

Then subscribe an email out-of-band (never in your `.tf`/state):

```
aws sns subscribe \
  --topic-arn "$(tofu output -raw sns_topic_arn)" \
  --protocol email \
  --notification-endpoint you@example.com
```

Per-project, tag-filtered, sharing that same topic:

```hcl
module "project_budget" {
  source  = "app.terraform.io/macgothub/cost-budget/aws"
  version = "~> 0.1"

  name                          = "my-project"
  monthly_limit                 = 15
  tag_filter_key                = "Project" # resources tagged Project = "my-project"
  activate_cost_allocation_tag  = true       # only true on ONE module instance per tag key

  create_sns_topic       = false
  existing_sns_topic_arn = module.account_budget.sns_topic_arn

  tags = { Project = "my-project" }
}
```

With a hard stop on a specific cost-bearing role (use sparingly -- see
the `enable_hard_stop` variable description):

```hcl
module "api_budget" {
  source  = "app.terraform.io/macgothub/cost-budget/aws"
  version = "~> 0.1"

  name                  = "my-public-api"
  monthly_limit         = 20
  enable_hard_stop      = true
  hard_stop_role_names  = [aws_iam_role.api_lambda.name]

  tags = { Project = "my-public-api" }
}
```

## Gotchas this module exists to avoid

- **A budget nobody subscribed to is worse than no budget.** It looks like
  coverage that doesn't exist. Every example above ends with a real
  subscriber.
- **An `alias/aws/sns`-encrypted topic silently drops every budget
  notification.** AWS Budgets can't get a data key from the AWS-managed
  key, so the publish fails -- same into-the-void failure, one layer down.
  This module's topic is unencrypted by default; to encrypt, use a
  customer-managed key policied for `budgets.amazonaws.com`. (Confirmed
  live: CloudWatch alarms hit the identical wall -- see `abuse-alarm`.)
- **A tag filter on an unactivated cost-allocation tag silently reports
  $0.** Not an error -- just a budget that looks like it's working and
  isn't. `activate_cost_allocation_tag = true` fixes it, but only set that
  on one module instance per tag key (activation is account-wide).
- **A hard stop is a real availability risk, not a free safety net.** AWS
  Budget Actions can't tell "this spike is abuse" from "this spike is a
  product launch going well." Off by default for a reason.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Project/budget name | -- |
| `monthly_limit` | USD monthly limit | -- |
| `tag_filter_key` | Cost-allocation tag key, or `null` for account-wide | `"Project"` |
| `activate_cost_allocation_tag` | Activate the tag (once per tag key, account-wide) | `false` |
| `notification_thresholds` | Actual-spend % thresholds | `[80, 100]` |
| `forecasted_threshold` | Forecasted-spend % threshold, or `null` | `100` |
| `create_sns_topic` | Create a dedicated topic | `true` |
| `existing_sns_topic_arn` | Reuse an existing topic instead | `null` |
| `sns_kms_key_id` | Customer-managed KMS key for the topic. Default null (unencrypted) -- AWS Budgets can't publish through `alias/aws/sns` | `null` |
| `enable_hard_stop` | Attach a deny-all budget action | `false` |
| `hard_stop_role_names` | Roles the hard stop locks down | `[]` |
| `tags` | Tags for created resources | `{}` |

## Outputs

| Name | Description |
|---|---|
| `budget_name` / `budget_arn` | The budget |
| `sns_topic_arn` | The topic notifications go to |
