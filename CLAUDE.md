# CLAUDE.md — terraform-aws-cost-guardrails

Persistent context for Claude Code. Read this before making changes.

---

## Owner

- **Name:** Derek McWilliams
- **Role:** Network Security Engineer (working toward DevSecOps)
- **GitHub:** MacGotHub
- Strong on AWS/networking; Python and GitHub Actions are stated growth
  areas, so explain those in detail. For infra-architecture tradeoffs he
  wants a recommended path, not an option menu — lead with a call.

---

## What this is

A small library of reusable OpenTofu/Terraform modules for the two things
every AWS side project needs and almost none have: a secure CI/CD trust
boundary, and a cost budget that actually reaches a human.

Extracted 2026-09-07 from three real projects —
[`satellite-tracker`](../satellite-tracker),
[`aws-detect-respond`](../aws-detect-respond),
[`orbital-watch`](../orbital-watch) — that had each independently rebuilt
some version of the same pattern. Motivated directly by the 2026-09-07
orbital-watch incident: an account budget with **zero notification
subscribers** alarmed into the void for a week while a runaway
DynamoDB-write cost accrued.

Not related to the sibling projects beyond shared ownership and being
their extraction source.

---

## Tooling

| Tool | Purpose |
|---|---|
| OpenTofu (`tofu`, 1.11.x) | The IaC these modules are written in |
| HCP Terraform private registry | Published to `app.terraform.io/macgothub` |
| GitHub Actions | CI — `.github/workflows/ci.yml` |
| Checkov | Consumers gate on it; see "Gotchas" for `CKV_TF_1` |

**AWS account** for the consuming projects: 351668480009, us-east-1.

---

## Repo structure

```
terraform-aws-cost-guardrails/
├── README.md              # Public-facing: what/why, module table, quickstart
├── CHANGELOG.md           # Shared version history — see "Versioning" below
├── LICENSE                # MIT
├── .github/workflows/ci.yml   # fmt -check, validate each module/example, tofu test
├── modules/
│   ├── oidc-cicd/         # Available. GitHub Actions OIDC trust boundary:
│   │                      #   read-only plan role, branch-pinned apply role,
│   │                      #   NO permissions attached (by design). Has tests/.
│   ├── cost-budget/       # Available. Monthly AWS Budget + a real verified
│   │                      #   SNS subscriber; optional tag filter; optional
│   │                      #   hard-stop IAM lockout (off by default).
│   └── kill-switch/       # Proposal only, and ONLY on branch
│                          #   `propose-kill-switch-module` (PR #1, closed
│                          #   unmerged). variables.tf + README, no main.tf.
└── examples/minimal/      # Complete working example, relative module paths
```

`abuse-alarm` (`modules/abuse-alarm/`) — per-resource CloudWatch alarms →
SNS. Same create/existing-topic pattern and out-of-band-subscribe rule as
`cost-budget`. Planned but not started: `waf-basic`.

---

## Design principles (from README — keep them true)

1. **Least privilege doesn't generalize — trust boundaries do.**
   `oidc-cicd` ships the trust policy shape and deliberately no
   permissions. A module that attached a "reasonable" IAM policy would be
   a soft AdministratorAccess grant the moment a second project used it.
2. **An alert nobody subscribed to isn't an alert.** Every module that
   notifies is built around a real, verified subscriber.
3. **Automated cost cutoffs are a real availability risk, not a free
   safety net.** `cost-budget`'s hard-stop is off by default and
   documented as such.

---

## Conventions

1. **Shared versioning.** One `vX.Y.Z` tag publishes *both* modules to the
   registry (no per-module tag prefix). Pre-1.0, so a minor bump can be
   breaking — consumers pin `~> 0.X.0` (patch-only), never `~> 0.X`.
2. **CHANGELOG entry + version bump for any behavior change** to a
   module's `main.tf`. The changelog notes which module actually changed.
3. **`tofu fmt` clean, `tofu validate` clean** for every module and
   example — CI enforces `fmt -check -recursive`.
4. **`tofu test` for logic worth pinning.** CI runs `tofu test` for any
   module with a `tests/` dir. `oidc-cicd` has one; use `mock_provider`
   so tests need no creds/network.
5. **`.terraform.lock.hcl` is gitignored.** These are reusable child
   modules — the lock belongs to the consumer, not here.
6. **Module READMEs document the tradeoffs**, not just inputs/outputs —
   match the existing `oidc-cicd` / `cost-budget` README style.
7. **`for_each` over `count`** for keyed collections, same as the sibling
   repos (the one exception: `count` on the whole optional
   `aws_iam_openid_connect_provider` in `oidc-cicd`).

---

## Release flow

1. PR → merge to `main` (CI: fmt, validate, test).
2. `git tag -a vX.Y.Z -m "..."` on the merge commit.
3. `git push origin vX.Y.Z` → HCP auto-publishes new versions of
   **both** `oidc-cicd/aws` and `cost-budget/aws`.
4. Bump consuming repos' `version = "~> 0.X.0"` in a follow-up PR each.

---

## Consuming these modules (what a caller needs)

- **HCP registry auth in CI.** `tofu init` needs `TF_TOKEN_app_terraform_io`
  to reach `app.terraform.io`. Consumers set a `TF_REGISTRY_TOKEN` GitHub
  secret (an `owners` team token, free-tier HCP has no dedicated team) and
  wire it onto the `tofu init` step in plan.yml/apply.yml.
- **Checkov `CKV_TF_1`** ("module sources use a commit hash") fails on any
  registry `module` block — it only understands git-source-at-SHA. The
  caller adds an inline `# checkov:skip=CKV_TF_1: registry source, pinned
  by version` on the `module` block.
- Migrating an existing hand-rolled setup onto `oidc-cicd` needs
  `moved {}` blocks (the roles/provider are already in state); verify with
  a local `tofu plan` before opening the PR. See the aws-detect-respond
  and satellite-tracker migration PRs for the worked recipe.

---

## What NOT to do

- **Don't attach permission policies inside `oidc-cicd`.** That's the
  whole point of the module — the trust boundary is generic, permissions
  aren't.
- **Don't default `cost-budget`'s hard-stop on**, and don't remove the
  "verified subscriber" requirement from any notifying module.
- **Don't introduce per-module tag prefixes** or otherwise break the
  single-tag-publishes-both model without a deliberate, documented switch.
- **Don't commit `.terraform.lock.hcl`.**
- **Don't re-derive the GitHub OIDC provider thumbprint from a live
  `data.tls_certificate` read.** That endpoint is CDN-fronted and the
  value churns; v0.3.0 uses a static thumbprint + `ignore_changes`. AWS
  hasn't verified this thumbprint for GitHub's endpoint since 2023.
- **Don't ship a module that "detects" anything** in `kill-switch` /
  `abuse-alarm` scope creep — `abuse-alarm` is the detector, `kill-switch`
  (if ever built) is a pure actuator.

---

## Current status

- **`oidc-cicd`** — v0.1.0 (initial) → v0.2.0 (`github_subject_prefix_override`
  for GitHub's immutable numeric-ID `sub` form) → **v0.3.0** (static
  provider thumbprint, drops the `tls` dependency). Consumed by
  `aws-detect-respond` and `satellite-tracker`, both migrated + applied.
- **`cost-budget`** — published at v0.3.0, but no repo consumes it via the
  module yet; the three siblings still have inline budgets.
- **`kill-switch`** — deferred. Design on branch
  `propose-kill-switch-module`. If revived: build the manual SSM-flag path
  first, skip auto-arm-from-alarm until trusted.
- **`abuse-alarm`** — built (`modules/abuse-alarm/`, 5 `tofu test` cases).
  Per-resource CloudWatch alarms → SNS. Ships as v0.4.0 when tagged. No
  repo consumes it yet.
- **`orbital-watch` OIDC migration** — not done; needs `cost-budget`
  extended for its killswitch-responder SNS wiring first.

---

## Open items / backlog

Ordered roughly by value-to-risk. Nothing here is urgent — everything
merged is applied and drift-free.

1. **Adopt `abuse-alarm`.** Built (`modules/abuse-alarm/`, PR pending
   review). Next: tag v0.4.0, then add a `module "abuse_alarm"` block to
   each project with alarms on its cost-bearing resources (DynamoDB write
   units, the voice Lambda's invocations, ECS task count), sharing the
   existing budget SNS topic, and subscribe the topic for real.

2. **`orbital-watch` OIDC migration.** Same recipe as
   aws-detect-respond / satellite-tracker, but `orbital-watch` also has an
   inline budget + budget-action + killswitch-responder SNS wiring, so
   `cost-budget` needs extending first (a scoped budget-action exec role
   input, and an existing-SNS-topic input for the killswitch path).
   Low priority — the inline code works, this is DRY-only.

3. **`kill-switch` module** — deferred. Design on branch
   `propose-kill-switch-module`. If picked up, build the manual SSM-flag
   path first; skip auto-arm-from-alarm until trusted. Four decisions to
   settle before writing `main.tf` (recommended answers in parentheses):
   - **ECS restore semantics:** on `safe`, restore `desiredCount` to a
     value stashed in SSM at arm time, or to a static per-service input?
     *(→ stash, with a static `restore_desired_count` fallback.)*
   - **Lambda stop action:** reserved-concurrency-0 for any listed
     function (blunt, 429s health checks too), or opt-in per function with
     a cooperative SSM check as the norm? *(→ concurrency-0 as the
     default; a switch that needs prior app cooperation has the same
     failure mode as the pattern it replaces. Also expose the param name
     so apps can layer a graceful response on top.)*
   - **Merge with `abuse-alarm`?** *(→ keep separate. `kill-switch` takes
     an SNS topic; anything publishes to it. `abuse-alarm`'s README shows
     the wiring.)*
   - **Responder code packaging:** inline `src/responder.py` +
     `data "archive_file"`, or a committed prebuilt zip? *(→ inline;
     ~60 lines, stdlib + boto3, no pip deps, so the determinism problem
     that bit satellite-tracker's layer doesn't apply. Keeps the module
     self-contained for registry consumers.)*

4. **Nice-to-haves:** bump the deprecated `actions/checkout@v4` etc. to
   Node-24 majors across all repos' workflows; a stale `hashicorp/tls`
   entry may sit in `satellite-tracker/opentofu/.terraform.lock.hcl` until
   someone runs `tofu init -upgrade` (harmless).
