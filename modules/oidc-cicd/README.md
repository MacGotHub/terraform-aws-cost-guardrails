# oidc-cicd

GitHub Actions OIDC trust boundary for one repo: a read-only **plan** role
any ref or PR can assume, and a read-write **apply** role only a push to
your default branch can assume. No static AWS access keys in GitHub
secrets, ever.

This module creates the trust policy shape only -- it attaches no
permissions. See [Why no permissions?](#why-no-permissions) below.

## Usage

```hcl
module "cicd" {
  source = "github.com/MacGotHub/terraform-aws-cost-guardrails//modules/oidc-cicd"

  name_prefix  = "my-project"
  github_owner = "my-github-user"
  github_repo  = "my-project"

  # First project in the account creates the OIDC provider. Every other
  # project reuses it -- AWS allows only one per URL per account.
  create_oidc_provider = true
  # existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"

  tags = { Project = "my-project" }
}

# Attach your own least-privilege policy -- this module deliberately
# doesn't do it for you.
resource "aws_iam_role_policy" "plan_read" {
  name = "my-project-plan-read"
  role = module.cicd.plan_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "CallerIdentity", Effect = "Allow", Action = "sts:GetCallerIdentity", Resource = "*" },
      # ... exactly the reads your plan step needs, and nothing else
    ]
  })
}
```

Matching GitHub Actions workflow:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  plan:
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/my-project-gha-plan
          aws-region: us-east-1
```

## Why no permissions?

Least-privilege IAM only means something if it's scoped to the resources
a given project actually owns. A module that ships a generic "here's a
reasonable CI policy" is really shipping a soft AdministratorAccess grant
the moment two projects share the pattern -- which is the opposite of the
point of doing OIDC role separation in the first place.

What *is* genuinely reusable, and what this module owns, is the trust
policy: the read/write split, the branch pin on the write role, and the
OIDC provider/thumbprint plumbing that's easy to get subtly wrong.
Permissions are yours to add, one PR at a time, growing on purpose as
your project grows -- see the sibling projects this module was extracted
from for what that looks like at a larger scale than the example above.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | Prefix for role names | -- |
| `github_owner` | GitHub org/user | -- |
| `github_repo` | Repo name | -- |
| `apply_branch` | Branch allowed to assume the apply role | `"main"` |
| `create_oidc_provider` | Create the account's OIDC provider | `true` |
| `existing_oidc_provider_arn` | Reuse an existing provider instead | `null` |
| `tags` | Tags for created resources | `{}` |

## Outputs

| Name | Description |
|---|---|
| `plan_role_arn` / `plan_role_name` | Read-only role |
| `apply_role_arn` / `apply_role_name` | Read-write, branch-pinned role |
| `oidc_provider_arn` | The provider ARN in use |
