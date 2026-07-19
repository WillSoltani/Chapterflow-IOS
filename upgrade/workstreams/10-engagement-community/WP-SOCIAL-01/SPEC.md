# WP-SOCIAL-01 — Make community and moderation surfaces truthful and safe

## Problem and verified root cause

SocialFeature exposes profile, pairs, gifts, referrals, and safety behavior while block/unblock/list/report endpoints are explicitly marked backend TODO. A visible production safety action cannot rely on fake/in-memory success or an invented contract.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Resolve D-SURFACE-01 and inventory every visible social/community action against current backend route/auth/validation/storage.
2. Complete coordinated additive backend/iOS contracts for approved safety actions, or remove/disable unsupported production entry points truthfully.
3. Keep block/report, account status, gifts, referrals, rewards, and entitlements server-authoritative and fail closed.
4. Remove/hash PII and private content from logs/analytics; define rate-limit, offline, cancellation, and uncertain-delivery behavior.
5. Provide accessible/localized confirmation, destructive consequences, error recovery, account switching, and exact navigation.
6. Prove every retained surface across the complete native matrix, including a real translated locale and non-color safety state.

## Acceptance criteria

### AC-SOCIAL-01-01

- Given the visible community surface inventory is compared to backend source
- When D-SURFACE-01 is applied
- Then every action is implemented under a verified contract or absent/truthfully unavailable

### AC-SOCIAL-01-02

- Given block/report storage or authority is unavailable
- When a safety action is attempted
- Then the operation fails closed and no fake local success claims protection

### AC-SOCIAL-01-03

- Given a gift/referral/reward response is missing or unknown
- When the UI reconciles
- Then no entitlement/reward is granted locally and actionable safe state appears

### AC-SOCIAL-01-04

- Given logs/analytics are captured during profile/pair/report flows
- When privacy checks run
- Then no email, username, private content, report details, token, or raw identifier appears

### AC-SOCIAL-01-05

- Given offline, rate-limit, cancellation, repeat tap, auth expiry, and A→B are exercised
- When the surface recovers
- Then destructive state, focus, and server truth remain consistent

### AC-SOCIAL-01-06

- Given every required native matrix dimension and a real translated locale
- When retained profile, pair, gift, referral, and safety states render
- Then content/actions remain localized, ordered, focused, comfortably targetable, and fail-closed without color-only meaning

## Lifecycle and adverse states

Cover missing endpoint, unauthorized, rate limit, moderation outage, uncertain delivery, repeated block/report, invitation expiry, gift claim authority, referral unknown state, offline, auth expiry, relaunch, and A→B.

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
- **Domain:** SocialRepository is the single social data owner; backend owns safety/reward state; UI never falls back to fakes in production.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Every retained action has exact method/path/auth/body/envelope/error/storage evidence and coordinated compatibility.
- **Compatibility:** Additive backend changes preserve other clients; unverified aliases/endpoints are rejected.
- **Migration:** Block/report or profile cache changes require account-scoped migration; no client moderation authority.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Rollback hides/disables unsupported UI and preserves fail-closed safety, never restores fake success.

## Explicit non-goals and release boundary

- Inventing safety endpoints
- Backend deployment
- PII logging
- Client-granted gifts/rewards/Pro
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/SocialFeature --parallel.
2. swift test --package-path Packages/Networking --parallel.
3. npm test in the exact backend worktree when backend source changes.
4. Semgrep/privacy log assertions.
5. targeted social/safety XCUITest and accessibility evidence.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
