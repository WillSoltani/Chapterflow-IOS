# WP-READER-01 — Make reading controls, chapter navigation, and preferences coherent

## Problem and verified root cause

Reader has substantial models and views, but composition wires only quiz. The NATIVE inventory
identifies `reader-toolbar.depth-option` and `reader-toolbar.tone-option` at verified 36-point minima,
below the 44-point default. Other motion, stale chapter/preference work, and exact relaunch navigation
also lack end-to-end proof.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Confirm one ReaderModel owner and retain/cancel every lifetime-sensitive chapter, preference, and progress task.
2. Reject stale chapter/tone/depth results and treat CancellationError separately.
3. Make every Reader control reachable at the 44-point default, including raising
   `ReaderToolbar.depthButton` and `ReaderToolbar.toneButton` from their verified 36-point minima to
   measured 44×44-or-larger hit regions. Preserve VoiceOver order/focus, localized labels, Reduce
   Motion/Transparency, keyboard/pointer behavior, compact layout, AX text, long text, and RTL. No
   exception is authorized for either named finding.
4. Persist reader preferences and position under account/book/chapter/variant identity with debounced durable writes.
5. Prove table of contents, previous/next chapter, background/foreground, relaunch, and adaptive reader layout.
6. Prove account A → sign out → account B cancels reader tasks and clears A's chapter, variant,
   position, preferences, cached content, and progress/session identity before B can render or write.

## Acceptance criteria

### AC-READER-01-01

- Given chapter A load is superseded by chapter B
- When A completes late
- Then Reader shows B only and cancellation does not overwrite state or surface an error

### AC-READER-01-02

- Given depth/tone/preference actions are repeated rapidly
- When work settles
- Then one authoritative state persists under the exact account/book/chapter/variant identity

### AC-READER-01-03

- Given inherited findings `reader-toolbar.depth-option` and `reader-toolbar.tone-option` plus all
  Reader controls rendered under compact/regular width, AX and long localized text, RTL, VoiceOver,
  Reduce Motion, and Reduce Transparency
- When geometry and interaction validation runs
- Then every depth/tone option exposes a measured hit region of at least 44×44 points without overlap
  or unreachable content; order, focus, localized names/values, selected traits, announcements, and
  equivalent keyboard/pointer actions remain usable; and the Reader-owned inventory contains zero
  `owner-closure-required` findings for both stable IDs

### AC-READER-01-04

- Given the app backgrounds or relaunches mid-chapter
- When the same account resumes
- Then exact chapter/variant/position is restored without double progress/session events

### AC-READER-01-05

- Given chapter navigation reaches first, middle, last, locked, offline, and failed states
- When controls update
- Then only valid destinations are enabled and recovery preserves context

### AC-READER-01-06

- Given account A has an open chapter, preferences, cached content, progress/session events, and
  in-flight reader work
- When A signs out and account B starts
- Then A state/tasks cannot render or commit for B and B resumes only owner-matching reader state

## Lifecycle and adverse states

Cover first chapter, cached/partial, malformed block, offline, cancellation, repeated controls, auth expiry, protected data, background/foreground, relaunch, A→B, orientation/window resizing, and memory pressure.

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
- **Domain:** ReaderModel owns reader state; AppFeature composes entry/exit only; persistence/network collaborators stay protocol-bound.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Reader chapter, preference, progress, and session contracts are verified before mutation; server owns unlocks.
- **Compatibility:** Unknown content blocks degrade safely and caches retain canonical encoding.
- **Migration:** Any position/preference key change requires read-old/write-new account-scoped migration tests.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Revert focused Reader changes without deleting existing progress.

## Explicit non-goals and release boundary

- Ask/annotation transport repair
- Quiz/review grading
- Audio session implementation
- Global shell redesign
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/ReaderFeature --parallel.
2. swift test --package-path Packages/Persistence --parallel when keys change.
3. swift test --package-path Packages/AppFeature --parallel.
4. targeted Reader XCUITests including relaunch and stale chapter.
5. WP-NATIVE-01 Reader accessibility/adaptive matrix plus exact owner-filtered closure of
   `reader-toolbar.depth-option` and `reader-toolbar.tone-option` with no exception.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
