# WP-JOURNEY-01 — Qualify the deterministic simulator product journey

## Problem and verified root cause

Current UI coverage proves isolated stubbed surfaces but not the complete Discover → Detail → Read/Listen → annotate/Ask → quiz/review → progress → relaunch → exact-resume loop. The previous package also combined simulator automation with signed-device/performance qualification, making the scope unbounded and allowing pre-final evidence to go stale.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. All dependencies must be integrated before this lane starts.

## Requirements

1. Commit a source-proven deterministic fixture and stable scenario manifest for the complete central loop without test-only authority leaking into production.
2. Cover named loading/cached/partial/empty/error/offline/cancellation/repeat/auth-expiry/background/relaunch/A→B integration scenarios.
3. Rerun native Light/Dark, compact/iPad, AX, real-locale, pseudo-long, RTL, VoiceOver, contrast, and motion evidence on this package's immutable candidate head.
4. Bind scenario results, app build, reviewer, exact-head CI, merge ancestry, and post-merge main to exact revisions while explicitly deferring signed-device/performance claims to WP-DEVICE-01.

## Acceptance criteria

### AC-JOURNEY-01-01

- Given a source-proven fixture account at Discover
- When the central journey runs through Detail, Start/Continue, Read/Listen, annotation/Ask, quiz/review, progress, relaunch, and resume
- Then every exact transition succeeds once with account and server authority preserved

### AC-JOURNEY-01-02

- Given every required adverse scenario in the committed manifest
- When deterministic injection and recovery run
- Then cached/private context, truthful status, cancellation, no duplicate mutation, and A→B isolation are proven

### AC-JOURNEY-01-03

- Given the exact candidate in Light/Dark, compact/iPad, AX, real-locale, pseudo-long, RTL, VoiceOver, contrast, and motion states
- When the journey native matrix runs
- Then required content/actions/focus remain usable across every declared simulator scenario

## Post-merge delivery verification

After AC-JOURNEY-01-01 through AC-JOURNEY-01-03 pass on the committed candidate, independently
review that exact head and apply `DELIVERY_POLICY.md`. Only after GitHub records merge may the
post-merge verifier bind local results, review, required CI, merge SHA, target containment, and
post-merge main CI. This is a delivery predicate, not a pre-merge AC. Signed-device/performance
completion remains explicitly pending WP-DEVICE-01.

## Invariants, compatibility, and rollback

Fixtures match WP-CONTRACT-02, contain no real private data, and never grant authority. The test support code is unavailable in production builds. Simulator evidence cannot claim Keychain/SIWA/APNs/extension/audio/device/performance behavior. iOS 18 outcomes and exact destination identity remain. Product defects return to their owner package; do not hide them by changing assertions.

## Test plan and definition of done

Run every exact selector/manifest command in [VALIDATE.md](VALIDATE.md), the full deterministic UI lane, app build, native matrix, exact-head independent review/CI, merge verification, and safe cleanup. Then WP-DEVICE-01 becomes ready; development-quality completion is not claimed before it passes.
