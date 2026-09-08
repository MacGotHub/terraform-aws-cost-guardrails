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
# GitHub rotates the TLS cert on token.actions.githubusercontent.com
# periodically (it did industry-wide in 2023) -- the thumbprint is fetched
# live via data.tls_certificate, never pasted as a literal.
# -----------------------------------------------

data "tls_certificate" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions[0].certificates[length(data.tls_certificate.github_actions[0].certificates) - 1].sha1_fingerprint]

  tags = var.tags
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
