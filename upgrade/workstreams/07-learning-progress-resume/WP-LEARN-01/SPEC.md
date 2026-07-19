# WP-LEARN-01 — Unify server-graded quiz and durable review mutations

## Problem and verified root cause

Quiz draft submission now preserves server authority, but review grading still has two potential durable owners: ReviewsRepository pending/optimistic FSRS state and SyncEngine reviewGrade. The composed loop does not prove pending grading, refresh, or no double submit.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Define one durable owner and stable identity for quiz/review submissions; migrate or quarantine the other path.
2. Keep correctness, pass, cooldown, unlock, FSRS scheduling, rewards, and progress server-authoritative.
3. Represent offline work as saved/pending grading, never a synthetic result, and require explicit replay where idempotency is unknown.
4. Reject stale attempts/results and repeated taps; refresh canonical progress/review state after accepted authority.
5. Provide accessible, localized quiz/review states across compact/iPad, AX text, offline, error, and resume.
6. Prove real-locale, pseudo-long, RTL, VoiceOver, keyboard/pointer, contrast, and Reduce Motion behavior on the package candidate head.
7. Register and populate `EngagementFeature/Resources/Review.xcstrings` with package-owned visible
   and accessibility copy, and prove quiz state is cleared across account A → sign out → account B.

## Acceptance criteria

### AC-LEARN-01-01

- Given a quiz or review action is tapped repeatedly
- When the network/outbox is observed
- Then one stable mutation is accepted and no duplicate grading/reward request occurs

### AC-LEARN-01-02

- Given the device is offline at submission
- When the user saves and relaunches
- Then the exact answers/grade remain durable and UI says pending rather than passed/failed

### AC-LEARN-01-03

- Given a stale attempt or review schedule is returned
- When the model reconciles
- Then it refreshes once, never auto-resubmits, and restores input only when identity still matches

### AC-LEARN-01-04

- Given legacy or duplicate review mutations exist
- When the new owner drains
- Then supported work migrates exactly once and unknown/uncertain work is retained or quarantined

### AC-LEARN-01-05

- Given server grading succeeds
- When the result and progress refresh
- Then authoritative correctness/schedule/unlock appears accessibly without local prediction

### AC-LEARN-01-06

- Given compact iPhone, resizable iPad, AX text, keyboard/pointer, a real locale, pseudo-long text, RTL, VoiceOver, contrast, and Reduce Motion
- When quiz and review question/result/pending/error/recovery states render
- Then content, answers, feedback, focus, targets, and non-color meaning remain usable and localized

### AC-LEARN-01-07

- Given account A has an in-progress quiz, answers, pending grading, or cached result
- When account A signs out and account B starts
- Then B sees none of A's quiz state, no stale task commits, and only B-scoped durable work can resume

## Lifecycle and adverse states

Cover first attempt, partial answer, rapid taps, offline, relaunch, stale attempt, rate limit/cooldown, auth expiry, cancellation, uncertain delivery, duplicate legacy work, A→B, background/foreground, and server evolution.

## Invariant matrix

- **Architecture:** Use the existing composition/domain owners and narrow protocols; do not introduce a production singleton, duplicate repository, router, session, or outbox.
- **Navigation:** Preserve exact destination identity and one replay; if this package has no navigation, prove it does not alter route ownership.
- **Concurrency:** Honor Swift 6 isolation, structured task lifetime, cancellation, stale-result rejection, and Sendable boundaries; no unsafe escape without a tested invariant.
- **Account:** Explicitly distinguish public from account-private state; no empty, anonymous, or fallback owner for authenticated durable data.
- **Authority:** Identity, account status, entitlements, unlocks, grading, rewards, and moderation remain server-authoritative and fail closed.
- **Privacy:** No secrets, tokens, private user content, identifiers, receipts, or raw URLs in logs, analytics, fixtures, screenshots, or evidence.
- **Accessibility:** All changed UI covers VoiceOver semantics/focus, AX Dynamic Type, contrast/non-color status, Reduce Motion/Transparency, and comfortable targets.
- **Localization:** All changed user/accessibility copy is localized in QuizFeature resources or
  `EngagementFeature/Resources/Review.xcstrings` and tested with a real locale, long text, and RTL.
- **Performance:** Do not block the main actor with file/JSON/image/network work; measure before making a performance claim and retain cancellation.
- **Observability:** Use fixed privacy-safe events and request IDs where diagnostic value exists; instrumentation failure cannot change product behavior.
- **Domain:** QuizFeature/Reviews domain model owns presentation; one SyncEngine-compatible durable envelope owns transport, never both repositories.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Quiz/review submit, check, progress, cooldown, and scheduling shapes come from current backend evidence; unknown idempotency forbids automatic replay.
- **Compatibility:** Migrate only recognized versioned envelopes; preserve server enum unknown values deliberately.
- **Migration:** Provide a versioned one-time migration or quarantine for PendingReviewGrade/reviewGrade overlap with deterministic prior-state fixtures.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Rollback preserves pending work and cannot restore local grading or duplicate drains.

## Explicit non-goals and release boundary

- Client-side quiz pass or FSRS authority
- Blind automatic replay of unknown-idempotency writes
- Reward/entitlement calculation
- Release StoreKit work
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/QuizFeature --parallel.
2. swift test --package-path Packages/EngagementFeature --parallel.
3. swift test --package-path Packages/SyncEngine --parallel.
4. swift test --package-path Packages/Persistence --parallel.
5. targeted offline/relaunch/stale-attempt quiz-review integration tests.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
