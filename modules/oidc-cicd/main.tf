# -----------------------------------------------
# GitHub Actions OIDC trust boundary for one repo: a read-only "plan" role
# any ref/PR can assume, and a read-write "apply" role only a push to
# var.apply_branch can assume. No static AWS keys involved -- GitHub
# presents a short-lived signed OIDC token, AWS trades it for temporary
# STS credentials scoped to one of these two roles.
#
# This module deliberately stops at the trust policy. It attaches NO
# permission policies to either role. Least-privilege IAM for what a
# given project's CI actually needs to read/write can't be genericized
# without turning into a de facto AdministratorAccess grant -- which
# defeats the point of doing OIDC at all. Attach your own
# aws_iam_role_policy / aws_iam_role_policy_attachment resources to
# plan_role_name / apply_role_name, scoped to exactly what that project's
# plan and apply steps touch. See examples/minimal for the pattern.
#
# Thumbprint handling (changed in v0.3.0): since July 2023, IAM does not
# use the thumbprint to verify token.actions.githubusercontent.com at all
# -- it's on AWS's list of OIDC IdPs backed by a trusted root CA. The API
# still requires the field to be non-empty on creation, so this passes a
# long-published GitHub Actions value, and `ignore_changes` keeps every
# subsequent apply from touching it.
#
# The old approach (v0.1-0.2) derived the value live from
# data.tls_certificate.certificates[last]. That endpoint is CDN-fronted
# and returns varying cert chains, so `[last]` came back different across
# reads and every apply planned a thumbprint update -- which needs
# iam:UpdateOpenIDConnectProviderThumbprint and, in a graph where the
# provider is a dependency of the CI write policy, a bootstrap-ordering
# dance to grant. Not worth it for a value AWS ignores.
#
# GITHUB_ACTIONS_OIDC_THUMBPRINT below is the intermediate CA fingerprint
# HashiCorp's own docs and AWS's GitHub OIDC guide have used for years.
# -----------------------------------------------

locals {
  # Only read for a fresh provider create; existing providers keep whatever
  # thumbprint their state already holds (see ignore_changes).
  github_actions_oidc_thumbprint = "6938fd4d98bab03faadb97b34396831e3780aea1"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [local.github_actions_oidc_thumbprint]

  tags = var.tags

  lifecycle {
    # AWS ignores this for GitHub's endpoint; don't let a drifted value
    # (e.g. one a pre-0.3.0 version of this module wrote) provoke an
    # update on every apply.
    ignore_changes = [thumbprint_list]
  }
}

check "oidc_provider_configured" {
  assert {
    condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != null
    error_message = "existing_oidc_provider_arn is required when create_oidc_provider is false."
  }
}

check "subject_identifies_one_repo" {
  assert {
    condition     = var.github_subject_prefix_override != null || (var.github_owner != null && var.github_repo != null)
    error_message = "Set github_owner and github_repo, or github_subject_prefix_override for GitHub's immutable numeric-ID subject form."
  }
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : var.existing_oidc_provider_arn

  # Name-based sub-claim matching (repo:OWNER/REPO:...) is the default: it
  # needs nothing but the owner and repo strings the caller already knows,
  # which is what makes this module drop-in on the first try.
  #
  # Some accounts' Actions tokens instead present the immutable numeric-ID
  # form (repo:OWNER@<owner_id>/REPO@<repo_id>:...), which survives a
  # repo/org rename where the name form silently stops matching. That form
  # needs a one-time ID lookup per repo, so it's opt-in via
  # github_subject_prefix_override rather than the default -- the module
  # treats whatever's passed there as opaque and just appends the same
  # ":*" / ":ref:..." suffixes it would for the derived form.
  sub_prefix = coalesce(
    var.github_subject_prefix_override,
    var.github_owner != null && var.github_repo != null ? "repo:${var.github_owner}/${var.github_repo}" : null,
  )
}

resource "aws_iam_role" "plan" {
  name = "${var.name_prefix}-gha-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "${local.sub_prefix}:*"
        }
      }
    }]
  })

  tags = var.tags
}

# Pinned to exactly one ref, unlike the plan role above -- a wildcard here
# would let a PR (including from a fork) assume a role that can change
# live infrastructure. This is the one trust-policy line that actually
# matters for the write role's safety; everything else is enforced by
# what permissions you choose to attach.
resource "aws_iam_role" "apply" {
  name = "${var.name_prefix}-gha-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.sub_prefix}:ref:refs/heads/${var.apply_branch}"
        }
      }
    }]
  })

  tags = var.tags
}
