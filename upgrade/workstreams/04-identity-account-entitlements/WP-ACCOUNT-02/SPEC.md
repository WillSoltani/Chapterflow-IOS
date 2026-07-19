# WP-ACCOUNT-02 — Make account deletion and backend account status fail closed

## Problem and verified root cause

The iOS delete endpoint posts an empty body while backend validation requires confirm DELETE and recent auth. Backend account-guard source permits access when status lookup fails, violating server-authoritative account state.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Align the iOS request and backend route on exact confirmation, recent-auth, errors, idempotency, and lifecycle semantics.
2. Make backend account guard deny safely on status-store failure with privacy-safe observability and bounded operational recovery.
3. Sequence background quiesce, APNs unregister attempt, provider deletion, local purge/quarantine, and sign-out truthfully.
4. Preserve account-private data until destructive success is authoritative; never show deletion success early.
5. Prove exact backend and iOS tests, while recording deployed revision as unknown until separately verified.
6. Make Settings deletion/status/recovery surfaces adaptive, localized, and accessible with destructive focus behavior preserved.
7. Resolve D-LOCK-01 inside the existing SettingsFeature owner: fully enforce the approved lifecycle
   and recovery policy or remove/label the production control unavailable; no dead security surface.
8. Prove Settings deletion, recovery, App Lock, cached account status, and in-flight task state is
   cleared or re-scoped across account A → sign out → account B.

## Acceptance criteria

### AC-ACCOUNT-02-01

- Given recent auth and the literal deletion confirmation are present
- When iOS sends the delete request
- Then the backend accepts the exact canonical body and rejects missing/wrong confirmation deterministically

### AC-ACCOUNT-02-02

- Given the backend account-status store times out or errors
- When a protected route is requested
- Then access fails closed with a safe error/request ID and no private payload

### AC-ACCOUNT-02-03

- Given deletion fails before authoritative completion
- When the app recovers
- Then private state is not silently purged, success is not shown, and retry/reauth remains actionable

### AC-ACCOUNT-02-04

- Given deletion succeeds authoritatively
- When scope teardown completes
- Then account work stops, appropriate local data is purged/quarantined, and signed-out state appears once

### AC-ACCOUNT-02-05

- Given backend source merges but no deployed revision is proven
- When package evidence is reported
- Then source completion and deployed behavior remain separate and no deployment claim is made

### AC-ACCOUNT-02-06

- Given compact iPhone, resizable iPad, AX text, keyboard/pointer, a real locale, pseudo-long text, and RTL
- When deletion, progress, failure, confirmation, and recovery states render
- Then consequences, actions, focus, comfortable targets, and non-color status remain understandable and localized

### AC-ACCOUNT-02-07

- Given D-LOCK-01 is resolved
- When the Settings App Lock surface and lifecycle are exercised
- Then approved enforcement/recovery is complete or the control is absent/truthfully unavailable

### AC-ACCOUNT-02-08

- Given account A has Settings, deletion/recovery, App Lock, cached status, and in-flight state
- When A signs out and account B starts
- Then A state and late tasks cannot render, authorize, delete, lock, or mutate B, and B starts from
  only owner-matching state

## Lifecycle and adverse states

Cover recent-auth expiry, repeated delete taps, timeout after server acceptance, provider failure, APNs unregister failure, offline, cancellation, backgrounding, relaunch mid-flow, subscription consequence, and A→B.

## Invariant matrix

- **Architecture:** Use the existing composition/domain owners and narrow protocols; do not introduce a production singleton, duplicate repository, router, session, or outbox.
- **Navigation:** Preserve exact destination identity and one replay; if this package has no navigation, prove it does not alter route ownership.
- **Concurrency:** Honor Swift 6 isolation, structured task lifetime, cancellation, stale-result rejection, and Sendable boundaries; no unsafe escape without a tested invariant.
- **Account:** Explicitly distinguish public from account-private state; no empty, anonymous, or fallback owner for authenticated durable data.
- **Authority:** Identity, account status, entitlements, unlocks, grading, rewards, and moderation remain server-authoritative and fail closed.
- **Privacy:** No secrets, tokens, private user content, identifiers, receipts, or raw URLs in logs, analytics, fixtures, screenshots, or evidence.
- **Accessibility:** All changed UI covers VoiceOver semantics/focus, AX Dynamic Type, contrast/non-color status, Reduce Motion/Transparency, and comfortable targets.
- **Localization:** All changed user/accessibility copy is localized and tested with long text and RTL where visible.
- **Performance:** Do not block the main actor with file/JSON/image/network work; measure before making a performance claim and retain cancellation.
- **Observability:** Use fixed privacy-safe events and request IDs where diagnostic value exists; instrumentation failure cannot change product behavior.
- **Domain:** Backend owns account status; iOS owns truthful orchestration and local cleanup only after authority.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** POST account delete body, recent-auth proof, errors, and account-guard storage behavior are exact route contracts.
- **Compatibility:** Prefer additive error/detail fields; coordinate any body transition so older clients fail safely.
- **Migration:** Destructive data behavior requires a separately tested purge/quarantine sequence; D-DATA-01 is not silently resolved here.
- **Decision:** D-LOCK-01 records threat model, timeout, protected-data, biometric/passcode-change,
  recovery, and accessibility behavior; absent policy defaults to removing/labeling the control.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Backend rollback must not restore fail-open access; iOS rollback must retain truthful deletion state.

## Explicit non-goals and release boundary

- Production deployment
- Deleting ownerless legacy data
- Automatic subscription cancellation claims without verified contract
- Release work
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/Networking --parallel.
2. swift test --package-path Packages/SettingsFeature --parallel.
3. swift test --package-path Packages/AuthKit --parallel.
4. npm test in the exact backend worktree.
5. targeted deletion/reauth XCUITest plus backend account-guard failure tests.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
