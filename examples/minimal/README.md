# Minimal example

Wires up both modules for a brand-new project: a secure OIDC CI/CD trust
boundary plus a real, subscribed cost budget. This is meant to be the
first commit of a new project's `opentofu/` -- copy it in, rename
`my-project`, and grow the plan/apply IAM policy from there as the
project grows.

```bash
tofu init
tofu plan
```

(Real `apply` needs AWS credentials and will create real resources --
this is here as a reference, not something to blindly run in CI.)
