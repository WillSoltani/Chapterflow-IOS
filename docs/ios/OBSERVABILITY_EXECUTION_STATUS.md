# Observability Execution Status

Last updated: 2026-07-15

## WP-OBS-01B rebased publication checkpoint

Status: Implementation is rebased and focused validation is complete on the isolated branch. The merge-order gate opened when `WP-BOOT-01B: Complete storage recovery and launch evidence` merged as PR #126; this checkpoint is ready for the single authorized push and draft PR.

- Finding: `CF-043`
- Starting base: `6bfa34160f1511e89f7ed2c182830bf8a60d4373` (`origin/main`, merged WP-OBS-01A PR #125)
- Required bootstrap foundation: `73acead1b24e9bfbd1ef7c9b8e822f72ea42f874` (merged WP-BOOT-01A PR #124)
- Rebased publication base: `d6445b9ea908736944a8b53654e87b1b638b0b22` (merged WP-BOOT-01B PR #126)
- Merge-order/ownership evidence: the BOOT-01B and OBS-01B file sets have zero overlap; the one OBS commit rebased without conflict
- Branch: `codex/wp-obs-01b-live-composition`
- Worktree: `/private/tmp/Chapterflow-IOS-wp-obs-01b`
- Authoritative workflow: `CI — Required`, aggregate context `CI / Required`

### Live composition and lifecycle

`AppModel` now creates the crash reporter before networking and delegates its single live `APIClient` construction to `LiveAPIClientComposition`. That factory creates exactly one fixed-capacity health recorder and one stable-order `CompositeAPIClientObserver` with two children: the health recorder and the existing `CrashBreadcrumbAPIObserver`. The same client continues to be shared by all live repositories and services; production composition does not take the optional no-op observer path.

The composite is synchronous and nonthrowing. It creates no task and performs no I/O. Each closed `APIRequestObservation` is offered once to each child in declaration order. Reporter unavailability and a child that rejects and contains its own error cannot alter the decoded result, thrown application error, retry behavior, or cancellation behavior.

`APIObservationHealthRecorder` uses `OSAllocatedUnfairLock` over private value state. Its fixed capacity is 128 events; append number 129 deterministically evicts the oldest event. Snapshots are immutable and expose only capacity, the already-sanitized typed events, an ephemeral process-local generation, and closed `signed_in`/`signed_out` state. The recorder creates no tasks, performs no encoding, and has no persistence path.

`AppModel.signOut()` clears and rotates the recorder as its first statement. Observation tracking also clears synchronously in the auth state's will-change callback, rejects completions while the transition is unsettled, then rearms against the resulting closed session state. `APIClient` captures the observer's opaque generation context once at logical request start and carries it through every retry attempt. Therefore an old-session request that finishes after rotation cannot repopulate the later session, while its API result and the context-free privacy-safe crash breadcrumb remain unchanged.

The request-start context change in `APIClient` is the narrow exception permitted by this work package: the focused race test failed against merged main because an old-session successful completion was retained after rotation. No event schema, safe-route logic, return value, error mapping, retry count, timeout, endpoint, or cancellation semantic changed.

### Privacy attack matrix

| Attack | Containment evidence | Result |
|---|---|---|
| Unbounded event growth | Public constant and snapshot capacity are 128; append 129 evicts event 1 | Contained |
| Stale completion after account transition | Request-start generation is compared under the recorder lock; mismatches are rejected | Contained |
| Account switch restores prior context | Transition clears and advances synchronously; unsettled transitions reject events | Contained |
| User/account correlation | Only a process-local integer generation and closed auth state are retained; no identity enters the API | Contained |
| URL, query, or dynamic route leakage | Recorder accepts only merged `APIRequestObservation`; reflection mutation verifies query and dynamic identifiers are absent | Contained |
| Body, header, token, raw error, or content leakage | Observer API accepts only the closed typed event; snapshot reflection scans forbidden values and field names | Contained |
| Crash reporter unavailable | No-op reporter composition preserves the decoded result and still records health exactly once | Contained |
| Child rejects an event | Self-contained rejecting observer cannot stop the later child | Contained |
| Recursive diagnostics work | Recorder/composite perform no network, disk, encoding, analytics, or task creation | Contained |
| Duplicate live observer graph | Repository-wide construction scan finds one production `APIClient`, inside `LiveAPIClientComposition`; live exact-once test reaches both sinks once | Contained |

### Changed files

AppFeature composition and lifecycle:

- `Packages/AppFeature/Sources/AppFeature/AppModel.swift`
- `Packages/AppFeature/Sources/AppFeature/LiveAPIClientComposition.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/APIObservationCompositionTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/AppModelTestSupport.swift`

CoreKit bounded observation:

- `Packages/CoreKit/Sources/CoreKit/Observability/APIClientObserver.swift`
- `Packages/CoreKit/Sources/CoreKit/Observability/APIObservationHealthRecorder.swift`
- `Packages/CoreKit/Sources/CoreKit/Observability/CompositeAPIClientObserver.swift`
- `Packages/CoreKit/Tests/CoreKitTests/APIObservationHealthRecorderTests.swift`
- `Packages/CoreKit/Tests/CoreKitTests/CompositeAPIClientObserverTests.swift`

Focused request-start race fix:

- `Packages/Networking/Sources/Networking/APIClient.swift`
- `Packages/Networking/Sources/Networking/APIClientRetrySupport.swift`
- `Packages/Networking/Tests/NetworkingTests/APIClientObservationSessionTests.swift`

Status:

- `docs/ios/OBSERVABILITY_EXECUTION_STATUS.md`

### Validation evidence

| Validation | Result |
|---|---|
| Baseline `swift test --package-path Packages/CoreKit` | Passed: 156 tests |
| Baseline `swift test --package-path Packages/Networking` | Passed: 75 tests |
| Baseline `swift test --package-path Packages/AppFeature` | Passed: 76 tests |
| Pre-fix old-session completion test | Failed as intended: stale success remained visible after session rotation |
| Post-rebase `swift test --package-path Packages/CoreKit` | Passed: 167 tests in 30 suites |
| Post-rebase `swift test --package-path Packages/Networking` | Passed: 76 tests in 6 suites |
| Post-rebase `swift test --package-path Packages/AppFeature` | Passed: 87 tests in 19 suites, including merged BOOT-01B coverage |
| Pre-rebase unsigned Debug generic iOS Simulator build | Passed after adding an ignored compile-only `Secrets.xcconfig` copied from the unusable template; live integrations were not exercised |
| Post-rebase `swiftlint lint --strict --reporter github-actions-logging` | Passed: 0 violations in 760 files |
| Fast worktree native-contract semantics | Passed: 83 operations, 93 producers, 29 matrix rows, 93 relations; no evidence update required |
| `git diff --check` | Passed before and after the final documentation/review update |

The initial unsigned build failed only because the clean worktree lacked ignored `Secrets.xcconfig`. The repository-approved compile-only template removed that environmental blocker, and the unchanged command then passed. One AppFeature test attempt exposed stale SwiftPM source enumeration after a new Networking helper file was introduced; the helper was moved into the already-enumerated retry-support source, and the corrected exact suite passed. Neither failure was retried blindly.

No full package matrix, UI suite, physical-device flow, real backend request, or live Sentry delivery was run locally, as required by the bounded validation plan. The exact-head app build and broad lanes remain delegated to `CI / Required`; AppFeature compiled and passed against the merged BOOT-01B source locally. There is no new UI, so accessibility and visual behavior are unchanged. The fixed in-memory bound, synchronous fan-out, and lock-isolated snapshots are the relevant performance checks.

### Independent privacy review

The one required fresh bounded read-only reviewer inspected the complete tracked diff, all seven then-untracked implementation/test files, and the merged privacy boundary. It returned `PASS` with no P0, P1, or P2 finding. No remediation cycle was required.

Its novel mutation reversed the child-context array returned by `CompositeAPIClientObserver.captureContext()` while preserving observer order. `liveCompositionExactOnce` kills that mutation: the health recorder receives the crash observer's unscoped context, rejects the event, and fails the exact-one health assertion while the breadcrumb child still records. Residual risk is limited to live Sentry SDK delivery not being exercised; the typed privacy boundary and API behavior isolation were verified locally.

### Contracts, migrations, scope, and rollback

No method, endpoint path, query, body, auth header behavior, response mapping, retry policy, contract artifact, persistence schema, migration, backend, bootstrap coordinator, endpoint policy, navigation, analytics-consent policy, release, App Store, TestFlight, signing, deployment, or PR #117 state changed. The user's main checkout and unrelated state remain untouched.

There is no rollout or data migration. Before merge, rollback is closing the PR and deleting the isolated branch/worktree. After squash merge, rollback is a reviewed revert of that one squash commit; no backend or data rollback is required.

Deferred work remains intentionally outside WP-OBS-01B: customer-visible diagnostics, analytics consent, persistent telemetry, user correlation, dashboards, production alerting, backend metrics, and release telemetry policy. After this package merges, the next shared-correctness wave is `WP-NET-01A` followed by the serialized auth/architecture sequence.

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
