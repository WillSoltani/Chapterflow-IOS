# Observability Execution Status

Last updated: 2026-07-14

## WP-OBS-01A Phase B publication checkpoint

Status: Stage B and bootstrap are verified merged; the branch is rebased, locally validated, and ready for its single Phase B push.

- Finding: `CF-043`
- Original Phase A base: `5df81f7722e856130854add1590585acddb9d6e7`
- Phase B base: `73acead1b24e9bfbd1ef7c9b8e822f72ea42f874` (`origin/main`)
- Stage B merge: `0830ba198d9271f7354f4f5d494d67fad1a478c1` (PR #123)
- Bootstrap merge: `73acead1b24e9bfbd1ef7c9b8e822f72ea42f874` (PR #124)
- Rebased implementation commit: `ce9a06034a0fb56c34317dc63c3f56cdaf2ee45b`
- Branch: `codex/wp-obs-01a-network-observation`
- Worktree: `/private/tmp/Chapterflow-IOS-wp-obs-01a`
- Publication checkpoint: this status commit is the final pre-push local state

### Implemented foundation

`APIRequestObservation` is the single `Sendable` event for one actual network attempt. Its closed schema contains method, sanitized route, one-based bounded attempt number, bounded monotonic `Duration`, outcome, optional valid HTTP status, optional strictly validated server request ID, and final/will-retry disposition. Outcomes distinguish success, HTTP failure, network failure, decoding failure, and cancellation.

`APIRouteSanitizer` discards query and fragment input before segment work, caps path bytes, segment bytes, segment count, and output bytes, performs one validated percent decode, and fails malformed or unreviewed routes to `/unknown`. It matches the reviewed Networking contract route grammar by position. Dynamic values become `:id`, numeric dynamic values become `:number`, and any static/dynamic template collision is treated as dynamic. It never hashes or retains concrete book, chapter, user, code, UUID, email, or other opaque route values.

Server request IDs fail closed unless they use the reviewed `req-` correlation namespace with a 16-48 character lowercase alphanumeric payload containing both a digit and a non-hex letter. Canonical/compact UUIDs, short codes, emails, and unreviewed identifiers are omitted.

`APIClient` now emits one observation after each attempt outcome is known. Success occurs only after successful decoding; decode failures never emit success. Network/auth/verifier retries keep their existing policy while exposing increasing attempt numbers and final/will-retry disposition. Cancellation remains `CancellationError`. `sendData` emits equivalent success, HTTP, network, and cancellation outcomes without changing returned bytes or thrown values.

`CrashBreadcrumbAPIObserver` accepts only the typed event and emits an allowlisted breadcrumb containing method, safe route, closed outcome, status, attempt, bounded duration bucket, retry disposition, and an optional validated request ID. It cannot receive a request/response, query, headers, body, token, or raw `Error`. Cancellation is info-level, never error-level. Production composition remains intentionally absent.

### Validation evidence

| Validation | Result |
|---|---|
| `swift test --package-path Packages/CoreKit` | Passed: 156 tests in 28 suites |
| `swift test --package-path Packages/Networking` | Passed: 75 tests in 6 suites |
| `swiftlint lint --strict --reporter github-actions-logging` | Passed: 0 violations in 751 files |
| `python3 scripts/contracts/verify_ios_incremental_contract_drift.py --layer worktree` | Passed: 83 operations, 93 producers, 29 matrix rows, 93 relations |
| `git diff origin/main..HEAD --check` and `git diff --check` | Passed |

The authoritative workflow is `CI — Required`, with exact pull-request aggregate context `CI / Required`. Legacy CI is manual-only. This diff does not match the exhaustive Contract Drift path filter; the required native contract semantics remain part of the authoritative aggregate. The full package matrix, app build, UI tests, simulator/device checks, and production telemetry checks were not run locally and remain delegated to exact-head GitHub CI where planned.

### Independent privacy review

The one bounded read-only reviewer initially found two P1 issues:

1. a position-independent static vocabulary could retain dynamic identifiers that collided with static words;
2. the original request-ID filter admitted UUID and short code-shaped values.

The single permitted remediation cycle replaced the vocabulary with position-aware route templates, added collision mutations, tightened the request-ID grammar, and added UUID/code rejection mutations. CoreKit, Networking, strict lint, contract semantics, and diff checks passed afterward. The same reviewer rechecked the final diff and returned `PASS` with no remaining P0, P1, or P2 finding. Its novel mutation—moving success emission before decode—was killed by the decode-failure tests.

### Contracts, migrations, and rollback

No endpoint method, path, query, body, authentication, retry policy, contract artifact, persistence schema, or backend contract changed. There is no migration. Before merge, rollback is to close the PR without merging. After squash merge, rollback is a reviewed revert of the single squash commit; no data or backend rollback is required.

### Remaining WP-OBS-01B work

`WP-BOOT-01A` is merged, but production composition remains deliberately deferred. `WP-OBS-01B` must compose `CrashBreadcrumbAPIObserver` at the production AppFeature/bootstrap composition root, prove the live observer is created once, and validate production-like scrubbed breadcrumb behavior. That later slice must separately handle approved diagnostics governance and must not broaden this foundation into analytics consent, persistent queues, session correlation/teardown, dashboards, backend metrics, or release telemetry policy without their owning work packages.

No AppModel, AppFeature, bootstrap, persistence, endpoint factory, contract artifact, backend, CI architecture, release, App Store, TestFlight, signing, PR #117, or unrelated user-worktree state was changed.
