variable "name_prefix" {
  description = "Prefix for the IAM role names this module creates, e.g. \"my-project\" -> \"my-project-gha-plan\" / \"my-project-gha-apply\"."
  type        = string
}

variable "github_owner" {
  description = "GitHub organization or user that owns the repo, e.g. \"my-github-user\". Required unless github_subject_prefix_override is set."
  type        = string
  default     = null
}

variable "github_repo" {
  description = "Repository name, without the owner, e.g. \"my-project\". Required unless github_subject_prefix_override is set."
  type        = string
  default     = null
}

variable "github_subject_prefix_override" {
  description = <<-EOT
    Overrides the derived "repo:OWNER/REPO" OIDC subject prefix verbatim,
    ignoring github_owner / github_repo.

    Use this for GitHub's immutable numeric-ID subject form --
    "repo:OWNER@<owner_id>/REPO@<repo_id>" -- which some accounts' tokens
    present instead of the plain name form. It survives a repo or org
    rename where the name form silently stops matching. Get the IDs from
    `gh api repos/OWNER/REPO --jq '{owner: .owner.id, repo: .id}'`, or read
    the `sub` claim off a real Actions token once.

    The module appends ":*" (plan role) and ":ref:refs/heads/<apply_branch>"
    (apply role) to whatever you pass here, exactly as it does for the
    derived form -- so pass only the prefix, no trailing colon.
  EOT
  type        = string
  default     = null
}

variable "apply_branch" {
  description = "Branch allowed to assume the write/apply role. Only a push whose ref matches this branch can get write access -- every other ref, including any PR, only ever gets the read-only plan role."
  type        = string
  default     = "main"
}

variable "create_oidc_provider" {
  description = <<-EOT
    Whether to create the GitHub Actions OIDC provider in this AWS account.

    AWS allows exactly one IAM OIDC provider per URL per account. If another
    project in this account already created one for
    token.actions.githubusercontent.com, set this to false here and pass its
    ARN via existing_oidc_provider_arn instead -- creating a second one for
    the same URL fails at apply time, on purpose (that's AWS enforcing the
    account-wide uniqueness, not a bug in this module).
  EOT
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing token.actions.githubusercontent.com OIDC provider to reuse. Required when create_oidc_provider is false; ignored otherwise."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
