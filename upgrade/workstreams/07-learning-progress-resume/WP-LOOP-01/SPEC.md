# WP-LOOP-01 — Compose the complete learning loop and exact durable resume

## Problem and verified root cause

ReadingFlowView wires only the quiz CTA. Listen, selection/Ask, notes/reflection, preferences, chapter transitions, loop completion, progress refresh, review scheduling, and exact resume exist in separate components but have no proven single composition path.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Compose existing feature owners through narrow closures/protocols without moving their state into AppFeature.
2. Wire Read/Listen, annotation/Ask, quiz/review, completion, progress refresh, next chapter, exit, and exact resume once.
3. Make transition identities stable and idempotent across repeated taps, auth replay, backgrounding, relaunch, and stale callbacks.
4. Preserve exact book/chapter/variant/position and restore the intended destination once after auth.
5. Add deterministic central-loop integration and UI tests using source-proven fixtures.
6. Localize package-owned shell/loop copy and prove the complete loop across every required native matrix dimension.

## Acceptance criteria

### AC-LOOP-01-01

- Given a user opens a book/chapter
- When the full learning session runs
- Then Reader, Listen, annotation/Ask, and quiz/review actions are reachable through one coherent context

### AC-LOOP-01-02

- Given quiz/review authority accepts completion
- When the loop advances
- Then progress refreshes once, next chapter/review state is exact, and no local unlock/reward is synthesized

### AC-LOOP-01-03

- Given the app backgrounds, terminates, or authentication interrupts mid-loop
- When the same account resumes
- Then the exact book/chapter/variant/position/action context returns once

### AC-LOOP-01-04

- Given a stale callback or repeated transition arrives
- When the composition owner handles it
- Then no duplicate session event, progress write, sheet, route, or completion occurs

### AC-LOOP-01-05

- Given account A exits and B signs in
- When the shell and loop inspect state
- Then B cannot observe/resume A's private context and A's work is stopped or safely retained

### AC-LOOP-01-06

- Given light/dark, compact iPhone, regular iPad, AX/VoiceOver, contrast, motion/transparency, real-locale, pseudo-long, RTL, and keyboard/pointer scenarios
- When the composed learning loop is traversed
- Then required content/actions remain localized, ordered, focused, comfortably targetable, and exact

## Lifecycle and adverse states

Cover first use, cached/partial content, offline, stream/audio failure, repeated actions, stale callbacks, auth expiry/reauth, background/foreground, termination/relaunch, A→B, locked next chapter, and server refresh conflict.

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
- **Domain:** AppFeature composes; Reader, Audio, Ask, Annotation, Quiz/Review, persistence, and routing retain their existing authoritative owners.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** All vertical package contracts must be merged and exact before loop composition; no adapter invents a missing server operation.
- **Compatibility:** Preserve existing book/chapter deep links and saved reader position; add compatibility mapping only with tests.
- **Migration:** No new omnibus loop store. Any resume-key evolution is a narrow versioned migration in its owning package.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Revert composition and integration tests while retaining independently correct vertical features.

## Explicit non-goals and release boundary

- Broad AppModel rewrite
- A second navigation or session state machine
- Local grading/unlock/reward authority
- Release analytics/attestation
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/AppFeature --parallel.
2. swift test --package-path Packages/ReaderFeature --parallel.
3. swift test --package-path Packages/QuizFeature --parallel.
4. unsigned Debug iOS Simulator build.
5. targeted Discover-to-resume central-loop XCUITest.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
