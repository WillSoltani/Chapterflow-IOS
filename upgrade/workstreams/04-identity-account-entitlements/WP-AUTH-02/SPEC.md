# WP-AUTH-02 — Align Keychain scope and reauthentication truth

## Problem and verified root cause

The app entitlement does not declare the group used by the authoritative token stores while extension
checks use a prefixed group; current source is internally inconsistent. Account deletion requires
recent auth. App Lock policy/surface belongs to WP-ACCOUNT-02 because SettingsFeature is its existing
single owner. Final signed runtime proof requires physical-device authority and therefore belongs to
WP-DEVICE-01, not this source package.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Inspect actual target build settings and every approved entitlement source; derive one valid
   least-privilege Keychain group without claiming signed runtime proof.
2. Make TokenStore/session restoration and approved extension access use the same explicit configuration without raw fallback identity.
3. Implement one production-completable recent-auth path through the authoritative Cognito/Amplify session, including cancel/failure/expiry.
4. Prove deterministic relaunch, token expiry/refresh, sign-out, account A→B, and protected-data
   behavior; delegate signed Keychain/SIWA runtime to WP-DEVICE-01.
5. Make sign-in and reauth surfaces adaptive, genuinely localized, and accessible across the complete WP-NATIVE-01 matrix.

## Acceptance criteria

### AC-AUTH-02-01

- Given approved target entitlement sources, build settings, and every Keychain query owner
- When the deterministic configuration contract runs
- Then one declared group matches every query and no missing-entitlement fallback is accepted

### AC-AUTH-02-02

- Given account A signs in, relaunches, refreshes, and signs out
- When the authoritative session lifecycle runs
- Then the same valid identity restores and all account-A work stops before scope teardown

### AC-AUTH-02-03

- Given account B then signs in
- When Keychain and presentation state are inspected
- Then no account-A token, data, task, or entitlement is exposed or reused

### AC-AUTH-02-04

- Given recent auth is required for a sensitive action
- When the user succeeds, cancels, goes offline, or the verifier expires
- Then the shared state machine reports each result truthfully without a second token authority

### AC-AUTH-02-06

- Given compact iPhone, resizable iPad, AX text, keyboard/pointer, a real locale, pseudo-long text, and RTL
- When sign-in and reauth states render
- Then content, actions, focus, targets, and recovery remain usable and localized without color-only meaning

## Lifecycle and adverse states

Cover first sign-in, relaunch, protected-data unavailable, expiry, concurrent refresh, cancellation, sign-out failure, scope teardown, A→B, and app background/foreground.

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
- **Domain:** SessionManager remains the single authority; Keychain configuration is composition/config, not feature-global state.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Cognito id_token remains the REST bearer token; provider and recent-auth behavior follows the pinned supported SDK path.
- **Compatibility:** Existing stored token encoding changes only with an explicit migration; old unsafe Apple exchange stays unavailable.
- **Migration:** If Keychain service/group changes, define safe read-old/write-new/delete-old sequencing with device tests; never silently lose sessions.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Rollback must preserve fail-closed provider surfaces and cannot restore a mismatched Keychain query.

## Explicit non-goals and release boundary

- Backend deployment
- TestFlight/App Store signing
- A second OAuth/token parser
- Settings/App Lock policy or implementation, which belongs to WP-ACCOUNT-02
- Logging tokens or entitlement values
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/AuthKit --parallel.
2. swift test --package-path Packages/AppFeature --parallel.
3. unsigned simulator build plus deterministic build-setting/entitlement-source contract checks.
4. focused sign-in/reauth XCUITests.
5. record WP-DEVICE-01 as the sole signed Keychain/SIWA relaunch and A-to-B runtime gate.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
