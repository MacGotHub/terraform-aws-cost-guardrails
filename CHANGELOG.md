# Changelog

Notable changes to the modules in this repo. Versions are shared: a single
`vX.Y.Z` tag publishes both `oidc-cicd` and `cost-budget` to the registry,
so every release below notes which module actually changed.

## [Unreleased]

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
