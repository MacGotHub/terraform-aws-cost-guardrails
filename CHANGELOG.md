# Changelog

Notable changes to the modules in this repo. Versions are shared: a single
`vX.Y.Z` tag publishes every module (`oidc-cicd`, `cost-budget`,
`abuse-alarm`) to the registry at that version, so each release below
notes which module actually changed.

## [Unreleased]

### abuse-alarm (new module)

- Per-resource CloudWatch metric alarms → SNS, keyed by short name.
  `namespace` + `metric_name` + `threshold` required per alarm; the rest
  default to a "Sum over 5 minutes, alarm on first breach" shape. Same
  create/`existing_sns_topic_arn` topic pattern as `cost-budget`, and the
  same "subscribe a real endpoint out of band" rule (no email in state).
  `notify_on_recovery` (default on) also pings on alarm → OK. Single-metric
  static-threshold only; composite / metric-math / anomaly-detection are
  out of scope.
- The created topic is **unencrypted by default** (`sns_kms_key_id = null`)
  -- CloudWatch alarms can't publish to an `alias/aws/sns`-encrypted
  topic, so `cost-budget`'s default would silently drop every alarm.
  Encrypt only with a customer-managed key policied for
  `cloudwatch.amazonaws.com`.
- Ships as v0.4.0 when tagged (new module = minor bump under the shared
  version).

## [0.3.0] - 2026-09-09

### oidc-cicd

- Stop deriving the OIDC provider thumbprint from a live
  `data.tls_certificate` read. GitHub's `token.actions.githubusercontent.com`
  endpoint is CDN-fronted and returns varying cert chains, so the derived
  value changed between reads and every `apply` planned a thumbprint
  update -- which needs `iam:UpdateOpenIDConnectProviderThumbprint` and, in
  a graph where the provider is a dependency of the CI write policy, a
  bootstrap-ordering workaround to grant. IAM has not used this thumbprint
  to verify GitHub's endpoint since July 2023 (trusted-root IdP list), so
  it's cosmetic.
- The provider now uses a fixed long-published thumbprint plus
  `lifecycle { ignore_changes = [thumbprint_list] }`. Existing providers
  keep whatever value their state holds -- adopting 0.3.0 shows no diff on
  the field. The `tls` provider is no longer a dependency.
- No interface change; `github_owner` / `github_repo` /
  `github_subject_prefix_override` all behave as in 0.2.0.

## [0.2.0] - 2026-09-07

### oidc-cicd

- Add `github_subject_prefix_override`: supply the OIDC subject prefix
  verbatim instead of deriving `repo:OWNER/REPO` from `github_owner` /
  `github_repo`. Intended for GitHub's immutable numeric-ID subject form
  (`repo:OWNER@<owner_id>/REPO@<repo_id>`), which keeps matching across a
  repo or org rename. `github_owner` / `github_repo` are now optional and
  ignored when the override is set. The plain name form is unchanged and
  remains the default -- existing callers need no changes.
- Add `tofu test` coverage for subject-prefix resolution (name form,
  override form, and `apply_branch` scoping).

## [0.1.0] - 2026-09-07

- Initial release: `oidc-cicd` and `cost-budget`, extracted and
  generalized from satellite-tracker, aws-detect-respond, and
  orbital-watch.
