# Development-Quality Completion Rubric

This rubric is a gate, not a score. Every applicable criterion must pass on the exact final revision;
`not applicable` needs a documented reason. “Release ready” is excluded.

| Dimension | Development-quality criterion | Required evidence |
|---|---|---|
| Product correctness | Every visible control is wired; all declared central-loop transitions preserve exact book/chapter/account identity; no false success or local grant of server authority. | Given/When/Then tests plus the deterministic central-loop UI journey and final-diff review. |
| Contracts | Method, path, auth, body, envelopes, aliases, enums, dates, pagination, errors, storage, and deployment provenance match current backend source or a coordinated additive contract. | Exact backend SHA, canonical fixtures derived from serializer/route shapes, iOS/backend tests, deployed evidence where runtime-dependent. |
| Architecture | One composition root, one session/account scope, one navigation owner per flow, one durable mutation owner per behavior, no feature-created production singleton. | Dependency/source audit, package tests, integration tests, no duplicate-owner finding. |
| Concurrency | UI models are main-actor isolated; mutable coordination is actor-isolated; cancellation and stale results are explicit; dangerous operations are structured/single-flight. | Swift 6 build, deterministic cancellation/race tests, targeted concurrency review. |
| Persistence/offline | Private data and outbox items are account-scoped; migrations preserve supported data; queued/syncing/failed/synced states are truthful; unknown mutations are never deleted as success. | Migration matrix, relaunch/account-switch/offline-reconnect tests, outbox invariant tests. |
| Native UI | Calm editorial hierarchy, semantic tokens, native controls/behavior, intentional loading/cached/empty/error/offline states, compact and regular-width adaptation. | Deterministic visual baselines, simulator screenshots, iPhone/iPad manual matrix, native-design review. |
| Accessibility | VoiceOver labels/values/traits/order/focus/announcements work; AX Dynamic Type does not lose content/action; contrast and non-color status pass; Reduce Motion/Transparency are respected; controls target 44×44 by default, with documented current-HIG evidence for smaller exceptions. | Accessibility Inspector/device runs, UI tests where deterministic, visual matrix, exception log. |
| Localization | User-facing and accessibility copy is localized; one real non-English locale, pseudo-localization, long text, pluralization, and RTL layouts preserve meaning/actions. | Catalog/string audit plus screenshot and UI matrix. |
| Reliability | Loading, cached/partial, empty, error/retry, offline, cancellation, repeated action, auth expiry, background/foreground, relaunch, and A→sign-out→B behavior are defined and tested where applicable. | Package-specific adverse-state matrix and central integration tests. |
| Performance | No main-actor network/file/JSON/image work; launch, scroll, reader pagination, memory, energy, image cache, audio, and download behavior meet recorded budgets without regressions. | Instruments/XCTest metrics on named device/runtime and exact revision; budget values established before optimization. |
| Security/privacy | Tokens stay in approved Keychain groups; sensitive data is absent from logs/analytics/evidence; account and entitlement authority fail closed; CI uses least privilege and immutable third-party action refs when changed. | Signed entitlement/Keychain proof, Semgrep/manual review, privacy log query, workflow review. |
| Testing | Changed package and affected dependents pass; critical flows have deterministic tests; visual assertions compare meaningful output; no skip/waiver/retry/threshold weakening. | Exact commands and counts; red-green proof for confirmed defects; fresh final-head reruns. |
| CI/delivery | Required CI selects the right risk lanes, all applicable checks succeed on the reviewed head, mergeability/protection/review gates hold, and post-merge `main` is verified. | GitHub exact-head checks, review evidence, merge SHA, post-merge run. |
| Maintainability | Package stays within scope/size envelope, public contracts are narrow, warnings/settings are not weakened, docs and rollback are current, and unused paths are removed only with proof. | Diff review, `git diff --check`, SwiftLint/SwiftFormat check, Periphery where justified, rollback exercise/analysis. |

## Milestone gates

### Feature complete

- All in-scope packages that change user behavior are merged.
- The central-loop journey passes with persisted relaunch/resume.
- No visible dead, fake, or contract-incompatible surface remains.

### Development-quality complete

- Every applicable row above passes.
- All R3 packages have independent specialist review and required device evidence.
- No unresolved P0, P1, or P2 finding remains.
- The final target revision passes required CI and program-level integration validation.

### Device validated

- Named signed device/OS/configuration evidence covers Simulator-insufficient behaviors.
- No identifiers, credentials, user content, receipts, tokens, or private URLs appear in evidence.

### Release ready — deferred

No development milestone implies release readiness. A separate owner-authorized release program must
define deployment, TestFlight, App Store, signing, production, and release-evidence gates.
