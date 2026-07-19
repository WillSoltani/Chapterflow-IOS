# WP-NOTIFY-01 — Complete exact notification, widget, and Live Activity routing

## Problem and verified root cause

APNs acknowledgement lifecycle and book/chapter routing have improved, but failed unregister durability, external-process account ownership, exact notification/widget/Live Activity destinations, unknown push types, and device behavior are incomplete.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Keep APNs registered only after backend acknowledgement and make register/unregister failures durably retryable under the owning account.
2. Bind widget/Live Activity/notification snapshots to an opaque owner and fail closed on mismatch/unknown owner.
3. Carry complete typed destination identity through notification actions, widgets, Spotlight/Handoff, quick actions, and auth replay.
4. Degrade unknown push/action types safely without private logging or fallback-to-wrong-screen behavior.
5. Prove deterministic permission/token/routing/account behavior and publish stable APNs/widget/Live Activity scenarios for exact-final device rerun in WP-DEVICE-01.
6. Consume WP-EXT-01 owner-bound snapshot migration, add genuine package/widget localization, and run
   every mandatory candidate-head native dimension for visible notification/widget states.

## Acceptance criteria

### AC-NOTIFY-01-01

- Given APNs registration or unregister fails
- When the app relaunches/reconnects under the same account
- Then the exact pending operation remains truthful and retries only when safe

### AC-NOTIFY-01-02

- Given an external snapshot owner is missing or differs from the active account
- When a widget/Live Activity reads it
- Then private content is not rendered and no fallback owner is invented

### AC-NOTIFY-01-03

- Given a notification/widget/action names a book, chapter, review, or other destination
- When auth and routing complete
- Then the exact destination opens once rather than only selecting a tab

### AC-NOTIFY-01-04

- Given an unknown or malformed push/action arrives
- When processing runs
- Then it degrades safely, performs no mutation, and records only privacy-safe diagnostics

### AC-NOTIFY-01-05

- Given permission, token, background, and A→B device scenarios run
- When evidence is captured
- Then registration, presentation, routing, and cleanup match the exact account/revision

### AC-NOTIFY-01-06

- Given every mandatory native dimension and a real translated locale
- When notification settings, permission/retry, widget, Live Activity, and routing states render
- Then copy, hierarchy, focus, announcements, targets, motion/transparency, and non-color status remain usable

## Lifecycle and adverse states

Cover notDetermined/denied/provisional/authorized, token rotation, offline register/unregister, auth expiry, unknown push, repeated action, background/terminated launch, A→B, protected data, widget reload, Live Activity stale content, and relaunch.

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
- **Domain:** NotificationAuthorizer owns permission; registration repository owns acknowledged token state; AppModel owns typed route replay; extensions read owner-bound snapshots.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Current backend device registration/unregistration and push payload types are source-verified; unknown fields do not grant behavior.
- **Compatibility:** Preserve known payload aliases only with fixtures; current canonical payload is encoded by backend.
- **Migration:** External snapshots/token retry state need versioned owner-bound migration or fail-closed invalidation.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Rollback removes new routing behavior but must retain pending unregister and owner privacy.

## Explicit non-goals and release boundary

- First-launch notification nag
- Direct UNUserNotificationCenter requests outside the owner
- Fallback tab routing for exact destinations
- APNs/production configuration mutation
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/NotificationsFeature --parallel.
2. swift test --package-path Packages/AppFeature --parallel.
3. widget/Live Activity target tests via xcodebuild.
4. targeted notification/deep-link XCUITests.
5. deterministic registration/routing tests; final APNs/widget/Live Activity/background/A-to-B matrix runs in WP-DEVICE-01.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
