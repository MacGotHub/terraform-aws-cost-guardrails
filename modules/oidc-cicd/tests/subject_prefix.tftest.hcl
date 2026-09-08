# Unit tests for OIDC subject-prefix resolution: the plain name form
# (github_owner / github_repo) and the immutable numeric-ID override.
# Mocked providers, create_oidc_provider = false -- no AWS creds, no
# network call to token.actions.githubusercontent.com.

mock_provider "aws" {}
mock_provider "tls" {}

variables {
  name_prefix                = "unit"
  create_oidc_provider       = false
  existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}

run "name_form_is_the_default" {
  command = plan

  variables {
    github_owner = "my-org"
    github_repo  = "my-repo"
  }

  assert {
    condition     = strcontains(aws_iam_role.plan.assume_role_policy, "\"token.actions.githubusercontent.com:sub\":\"repo:my-org/my-repo:*\"")
    error_message = "plan role should match repo:OWNER/REPO with a wildcard suffix"
  }

  assert {
    condition     = strcontains(aws_iam_role.apply.assume_role_policy, "\"token.actions.githubusercontent.com:sub\":\"repo:my-org/my-repo:ref:refs/heads/main\"")
    error_message = "apply role should pin repo:OWNER/REPO to refs/heads/<apply_branch>"
  }
}

run "override_is_used_verbatim_for_the_immutable_id_form" {
  command = plan

  variables {
    github_subject_prefix_override = "repo:my-org@188585672/my-repo@1305326446"
    # github_owner / github_repo deliberately unset
  }

  assert {
    condition     = strcontains(aws_iam_role.plan.assume_role_policy, "\"token.actions.githubusercontent.com:sub\":\"repo:my-org@188585672/my-repo@1305326446:*\"")
    error_message = "plan role should use the override string verbatim, then append :*"
  }

  assert {
    condition     = strcontains(aws_iam_role.apply.assume_role_policy, "\"token.actions.githubusercontent.com:sub\":\"repo:my-org@188585672/my-repo@1305326446:ref:refs/heads/main\"")
    error_message = "apply role should use the override string verbatim, then append :ref:refs/heads/<apply_branch>"
  }
}

run "apply_branch_feeds_the_apply_role_only" {
  command = plan

  variables {
    github_owner = "my-org"
    github_repo  = "my-repo"
    apply_branch = "release"
  }

  assert {
    condition     = strcontains(aws_iam_role.apply.assume_role_policy, "repo:my-org/my-repo:ref:refs/heads/release")
    error_message = "apply role should pin to the configured apply_branch"
  }

  assert {
    condition     = !strcontains(aws_iam_role.plan.assume_role_policy, "refs/heads/")
    error_message = "plan role must stay branch-agnostic (wildcard suffix only)"
  }
}
