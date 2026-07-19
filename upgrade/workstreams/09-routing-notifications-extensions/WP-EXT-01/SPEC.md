# WP-EXT-01 — Make extension process data owner-safe and transactional

## Problem and verified root cause

Share/Action capture writes a durable ownerless outbox, while AppModel drain intentionally preserves
it because attribution is unsafe. No validated account-bound import→persist→clear path exists.
Separately, widget/shared snapshots are ownerless at the model/writer/publisher and therefore cannot
be made private-safe by changing only the reader. Both are one cross-process envelope boundary owned
here under the persistence-schema lock.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Resolve D-DATA-01 and version the minimum extension-safe envelope without exposing the main app store.
2. Keep capture truthful while signed out or protected data is unavailable; claim saved only after durable outbox write.
3. On app import, read, validate, authorize attribution, persist under the exact account, then clear only that accepted item.
4. Quarantine malformed/unknown/foreign items with privacy-safe diagnostics and explicit recovery/discard behavior.
5. Prove interruption, duplicate import, relaunch, and A→B deterministically; publish stable process-kill scenarios for exact-final device rerun in WP-DEVICE-01.
6. Version outbound shared snapshots with an opaque owner from the authoritative account scope; the
   model/writer reject missing owner and publish the interface consumed later by WP-ENGAGE-01/NOTIFY-01.
7. Consume the integrated WP-NATIVE-01 Share/Action presentation and real target-owned translations,
   then validate capture, signed-out, error, and success states in every mandatory native dimension;
   this package never edits those extension targets or catalogs.

## Acceptance criteria

### AC-EXT-01-01

- Given Share/Action capture occurs while signed out or the app is absent
- When the extension completes
- Then a complete versioned item is durable and success is shown only after the write

### AC-EXT-01-02

- Given D-DATA-01 authorizes an item's attribution and account A is active
- When the main app drains
- Then it validates, imports, persists, then clears exactly once under A

### AC-EXT-01-03

- Given an item is malformed, unknown, owner-conflicting, or import persistence fails
- When the drain runs
- Then the item remains recoverable/quarantined and no false success or deletion occurs

### AC-EXT-01-04

- Given account A has pending extension items and B becomes active
- When B drains
- Then B cannot see, claim, clear, or import A/unknown content without approved policy

### AC-EXT-01-05

- Given the extension or app terminates between read/persist/clear
- When the flow resumes
- Then idempotency prevents duplication and recoverable data survives

### AC-EXT-01-06

- Given account A publishes a shared widget/Live Activity snapshot and B or no account reads it
- When ownership is checked across model/writer plus the declared publisher/reader interface contract
- Then only matching opaque owner state is usable and missing/mismatched legacy state is quarantined

### AC-EXT-01-07

- Given every mandatory native dimension and a real translated locale
- When Share/Action capture, signed-out, error, and success states render
- Then copy, focus, announcements, targets, motion/transparency, and non-color status remain usable

## Lifecycle and adverse states

Cover signed out, protected data unavailable, low storage, extension timeout, malformed URL/text, duplicate capture, kill at every transaction boundary, relaunch, auth expiry, A→B, schema evolution, and user discard/recovery.

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
- **Domain:** Extensions write an extension-safe file/outbox only; AppFeature performs account-authorized import; neither extension opens main SwiftData. Persistence owns both inbound/outbound versioned envelopes; WP-NATIVE-01 owns Share/Action presentation and catalogs, while WP-ENGAGE-01 and WP-NOTIFY-01 own publisher/reader conformance after this package.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** D-DATA-01 attribution policy and versioned envelope are mandatory; imported target contract is source-verified.
- **Compatibility:** Readers accept only verified prior envelope versions and write canonical current format.
- **Migration:** Retain/quarantine pre-owner items until policy; no automatic assignment or deletion.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Rollback leaves pending files recoverable and never clears after a failed import.

## Explicit non-goals and release boundary

- Opening main SwiftData from extensions
- Assigning ownerless content to current account by default
- Clearing before durable import
- App Store extension submission work
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/AppFeature --parallel.
2. Persistence envelope tests and SharedExtensionKit behavior through the Xcode extension host.
3. targeted extension import XCUITest/host test.
4. kill-boundary and A-to-B deterministic tests.
5. deterministic transaction-boundary tests; final App Group/protected-data/share/action process matrix runs in WP-DEVICE-01.
6. snapshot owner migration plus candidate-head extension native matrix.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
