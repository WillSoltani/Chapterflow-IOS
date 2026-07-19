# WP-OFFLINE-01 — Make downloads and offline synchronization restorable

## Problem and verified root cause

Downloads and SyncEngine exist, but exact durable asset commit, storage accounting, eviction, unknown mutation handling, real reconnect, relaunch, and account-switch behavior are not proven as one truthful offline outcome.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Define a versioned download manifest and completion rule that commits all required assets and records before success.
2. Use stable account/book/asset and mutation identities with resumable transfer and bounded retries only where safe.
3. Keep queued, downloading, paused, syncing, failed, and complete states distinct; auth failure pauses, not succeeds.
4. Quarantine unknown/malformed mutations and preserve uncertain delivery; enforce ordering and idempotency.
5. Prove relaunch, storage pressure/eviction, deletion, real offline/reconnect, backgrounding, and A→B isolation.
6. Localize every package-owned download/sync/storage status and prove it across the complete native matrix.

## Acceptance criteria

### AC-OFFLINE-01-01

- Given a download is interrupted after some assets arrive
- When the app relaunches and resumes
- Then only missing validated assets continue and the book is not marked complete early

### AC-OFFLINE-01-02

- Given storage is low or an asset is corrupt/expired
- When the manager reconciles
- Then state is actionable, accounting is correct, text remains available where cached, and no unrelated data is deleted

### AC-OFFLINE-01-03

- Given a mutation is unknown, malformed, or uncertain
- When the drain evaluates it
- Then the item is quarantined/retained and never removed as a successful no-op

### AC-OFFLINE-01-04

- Given authentication expires or account A signs out during work
- When the engine quiesces before B starts
- Then work pauses safely and B cannot see, delete, or drain A's assets/mutations

### AC-OFFLINE-01-05

- Given real connectivity transitions offline to online
- When eligible work resumes
- Then ordering/idempotency holds and UI distinguishes local cache from freshly synchronized truth

### AC-OFFLINE-01-06

- Given every required native matrix dimension and a real translated locale
- When download, sync, storage, offline, error, and recovery states render
- Then status/actions remain localized, ordered, focused, comfortably targetable, and non-color-only

## Lifecycle and adverse states

Cover first download, pause/resume/cancel, partial asset, expired URL, checksum/corruption, low storage, eviction, app kill/relaunch, background transfer, auth expiry, A→B, unknown mutation, uncertain response, and real network change.

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
- **Domain:** One download manager and one SyncEngine journal; settings presents state but does not own transfer.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Asset manifests, URL expiry/refresh, write idempotency, and server reconciliation are verified before automatic retry.
- **Compatibility:** Versioned manifests/journals migrate recognized fields and quarantine unknown formats.
- **Migration:** Test every supported prior manifest/outbox version and account namespace; destructive reset requires explicit authority.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Preserve recoverable assets and mutations; rollback must not delete unknown/pending work.

## Explicit non-goals and release boundary

- Arbitrary retry-to-success
- Unbounded cache growth
- Cross-account cache keys
- Production background configuration changes
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/SyncEngine --parallel.
2. swift test --package-path Packages/Persistence --parallel.
3. swift test --package-path Packages/SettingsFeature --parallel.
4. deterministic storage/relaunch/account-switch integration tests.
5. physical-device network/background/storage/memory matrix.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
