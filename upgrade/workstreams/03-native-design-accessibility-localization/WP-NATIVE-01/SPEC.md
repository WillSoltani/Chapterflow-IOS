# WP-NATIVE-01 — Establish deterministic native evidence and accessibility foundations

## Problem and verified root cause

Stored gallery images contain a prohibited placeholder, light/dark artifacts are effectively equivalent, and current render guards prove only that an image object exists. The app is English/Base-only, shared focus/announcement/touch-target behavior is inconsistent, and no executable inventory closes visible localization and accessibility debt.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the exact lane base.

## Requirements

1. Pin deterministic data, locale, calendar, clock, animation, appearance, device, font, and candidate-head inputs.
2. Reject placeholder/equivalent/missing/mismatched baselines; use pixel comparison only for stable content and semantic/manual evidence for OS chrome.
3. Provide shared, narrow DesignSystem primitives for focus/announcement, non-color status, motion/transparency, and comfortable targets without redesigning features.
4. Generate a machine-readable localization inventory and touch-target inventory with named owner packages and 44-point defaults; any 28–43-point exception requires adjacency and equivalent accessibility justification.
5. Define exact compact/iPad/AX/real-locale/pseudo-long/RTL/contrast/motion scenario and artifact schemas that every visible package reruns on its own candidate head.
6. Add one project-owned filesystem-synchronized `ChapterFlowUITests/UpgradeEvidence` source group so
   later packages can create only their declared exact Swift test file without editing the Xcode
   project or sharing a broad UI-test write root.
7. Localize the visible Share and Action extension capture/signed-out/error/success states in their
   target-owned catalogs with at least one real non-English translation, and include them in the
   deterministic locale, RTL, focus, announcement, non-color, motion/transparency, and target matrix.
8. Provide a deterministic paired iOS performance runner that builds current-main before candidate,
   pins device/OS/toolchain/fixture, uses XCUITest metrics plus declared Instruments templates,
   retains raw samples/xcresults/traces, and consumes but cannot relax the predeclared budgets.

## Acceptance criteria

### AC-NATIVE-01-01

- Given placeholder, equivalent Light/Dark, missing, or dimension-mismatched artifacts
- When baseline validation runs
- Then it fails with a stable actionable reason before approval

### AC-NATIVE-01-02

- Given a deterministic stable content surface
- When Light and Dark baselines are captured and compared
- Then metadata binds dimensions/inputs/head and adaptive semantic differences are asserted

### AC-NATIVE-01-03

- Given compact, resizable iPad, and AX-size fixtures
- When layout assertions run
- Then required content/actions remain present without clipping, overlap, or unreachable focus

### AC-NATIVE-01-04

- Given app plus Share/Action extension surfaces in a real non-English locale, pseudo-long text,
  plurals/formatting, and RTL
- When the semantic matrix runs
- Then meaning, action order, reading order, and semantic media direction are preserved from each
  target-owned catalog

### AC-NATIVE-01-05

- Given stable content and OS-dependent chrome/material surfaces
- When each surface is classified
- Then stable content uses deterministic comparison and unstable chrome uses named semantic/manual evidence without brittle thresholds

### AC-NATIVE-01-06

- Given every visible production surface in the inventory, including Share and Action extensions
- When localization and target scans run
- Then each string/surface has an owner package and every target is at least 44×44 points or has an explicit 28–43-point exception with equivalent access

### AC-NATIVE-01-07

- Given a later package creates its declared exact file under `ChapterFlowUITests/UpgradeEvidence`
- When Xcode target-membership validation inspects the project and compiles the UI-test target
- Then that file is compiled exactly once without a later package editing `project.pbxproj`

### AC-NATIVE-01-08

- Given focus/announcement, semantic status, contrast, motion/transparency, and target primitives
- When deterministic DesignSystem accessibility tests exercise their normal and adverse states
- Then VoiceOver values/traits/order/focus/announcements, non-color meaning, increased contrast, Reduce Motion/Transparency, and equivalent-access target behavior remain correct

## Invariants, compatibility, and rollback

The harness and shared primitives do not own feature redesign or product authority. This package's
visible product edit is limited to Share/Action localization and accessibility presentation; it does
not change their outbox transaction semantics. Evidence contains no private content, identifiers, or tokens. Feature packages generate their own candidate-head artifacts and close their assigned inventory. The synchronized UI-test group grants ownership only to each exact package-declared test file; later packages never edit the project or another package's tests. iOS 18 retains the same user outcome as enhanced APIs; there is no universal spacing-grid claim. Revert harness, project membership, primitives, extension localization, metadata, and baselines together; never retain silent skips or mass-approved baselines.

## Test plan and definition of done

Run every exact selector in [VALIDATE.md](VALIDATE.md), the full DesignSystem suite, native-evidence UI selectors, inventory schema checks, app build, independent exact-head review, required CI, merge verification, and safe cleanup. Missing runtime/manual evidence is blocked, not fabricated.
