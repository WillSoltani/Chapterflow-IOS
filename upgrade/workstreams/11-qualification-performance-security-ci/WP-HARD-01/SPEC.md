# WP-HARD-01 — Harden risk-selective development CI and its supply chain

## Problem and verified root cause

`pr-v2.yml` is the authoritative required workflow and passes `actionlint`, but the planner needs
executable event/path coverage. Offline evidence also finds mutable action tags and permission/cache
risks in contract-drift, legacy, and release workflows. Development hardening must preserve required
check identity and coverage without executing or coupling to release.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source
`858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every
anchor and live branch-protection/check contract on the lane's exact base.

## Functional and non-functional requirements

1. Add table-driven planner tests for docs, package, shared, UI, contract, workflow, merge-queue,
   schedule/manual, cancellation, and main events.
2. Audit triggers, permissions, expression injection, action refs, artifacts/caches, credentials,
   fork trust, and public-runner boundaries with `actionlint` and offline `zizmor`.
3. Pin every retained third-party action to an immutable reviewed commit and document the readable
   version; use least-privilege top/job permissions and `persist-credentials: false` where possible.
4. Keep `CI / Required` and branch-protection check names stable; preserve failure provenance and
   never turn missing secrets, cancelled work, or planner errors into a green skip.
5. Inspect release workflows read-only and record security findings for separately authorized release
   planning; this package edits and validates only the three declared development workflows and never dispatches release.

## Acceptance criteria

### AC-HARD-01-01

- Given the supported event/path matrix is supplied to the CI planner
- When table-driven planner tests execute
- Then every required risk lane runs or skips only for an asserted safe reason and `CI / Required` remains authoritative

### AC-HARD-01-02

- Given workflows are audited under fork and same-repository threat models
- When permissions, expressions, credentials, artifacts, caches, and triggers are inspected
- Then no high-severity exposure or unjustified write permission remains

### AC-HARD-01-03

- Given a retained external Action is referenced
- When the workflow/config inventory is validated
- Then it uses an immutable commit SHA with a readable version comment and safe credential persistence

### AC-HARD-01-04

- Given a planner error, cancellation, cache miss, or absent optional secret occurs
- When the required workflow resolves
- Then failure/skip provenance is explicit and no required coverage silently becomes green

## Lifecycle and adverse states

Cover fork/same-repo pull requests, merge queue, main, schedule/manual comparison, path deletion,
renames, package-graph failure, cache miss/hit/poisoning, cancellation, runner/Xcode drift, absent
optional secrets, and malicious expression-like input.

## Invariant matrix

- **Architecture:** CI planner remains deterministic and repository-native; no agentic workflow is introduced.
- **Navigation:** Not applicable; the package proves it does not change product routes.
- **Concurrency:** Duplicate jobs/caches cannot corrupt shared state; cancellation remains truthful.
- **Account:** CI never consumes product-account data.
- **Authority:** A workflow cannot grant product or release authority.
- **Privacy:** Logs/artifacts expose no token, secret, private content, raw identifier, or credential-bearing checkout.
- **Accessibility:** Not applicable to workflow source; no product UI is changed.
- **Localization:** Not applicable to workflow source; no product copy is changed.
- **Performance:** Efficiency changes require measured run evidence and cannot reduce coverage.
- **Observability:** Job/lane failure and skip reasons remain fixed, privacy-safe, and diagnosable.
- **Domain:** `CI / Required` remains the development merge gate; release remains separate and unauthorized.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Current branch protection, required check names, planner inputs/outputs, and
  GitHub event semantics are re-read before editing.
- **Compatibility:** Check names and coverage stay stable or are coordinated before merge.
- **Migration:** Cache-key changes invalidate safely; there is no product migration.
- **Rollout:** Development source only after exact-head validation; no workflow dispatch is needed.
- **Rollback:** Revert the focused workflow/planner change without restoring mutable refs or broad permissions.

## Explicit non-goals and release boundary

- App/runtime performance qualification, CoreKit observability changes, release execution, matrix
  reduction for speed, agentic Actions, deployment, App Store, TestFlight, signing, or PR #117.

## Test plan

1. `python3 -m unittest scripts.tests.test_ci_plan scripts.tests.test_ci_checks`.
2. `actionlint .github/workflows/pr-v2.yml .github/workflows/contract-drift.yml .github/workflows/pr.yml`.
3. `zizmor --offline --no-progress --min-severity medium .github/workflows/pr-v2.yml .github/workflows/contract-drift.yml .github/workflows/pr.yml`.
4. focused assertions for pins, permissions, checkout credentials, cache keys, and required check names.
5. after publication, delivery policy verifies exact-head GitHub required checks without dispatching release workflows.

## Definition of done

Every AC and invariant maps to the exact committed candidate in [VALIDATE.md](VALIDATE.md); planner
tests and security validators pass; independent exact-head review has no P0/P1/P2; required GitHub
checks pass without release execution; merge/post-merge verification succeeds; only then may the
recorded owner release claims and package resources. Product performance remains owned by feature
packages and final `WP-DEVICE-01` qualification.
