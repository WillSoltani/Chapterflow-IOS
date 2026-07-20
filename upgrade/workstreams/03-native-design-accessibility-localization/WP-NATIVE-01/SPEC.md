# WP-NATIVE-01 — Establish deterministic native evidence and accessibility foundations

## Problem and verified root cause

Stored gallery images contain a prohibited placeholder, light/dark artifacts are effectively equivalent, and current render guards prove only that an image object exists. The app is English/Base-only, shared focus/announcement/touch-target behavior is inconsistent, and no executable inventory closes visible localization and accessibility debt.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the exact lane base.

## Requirements

1. Pin deterministic data, locale, calendar, clock, animation, appearance, device, font, and candidate-head inputs.
2. Reject placeholder/equivalent/missing/mismatched baselines; use pixel comparison only for stable content and semantic/manual evidence for OS chrome.
3. Provide shared, narrow DesignSystem primitives for focus/announcement, non-color status, motion/transparency, and comfortable targets without redesigning features.
4. Generate machine-readable localization and touch-target inventories with stable path-plus-symbol/control IDs, named owner packages, measured or explicitly unverified dimensions, and separate compliance status. A 28–43-point exception requires adjacency and an equivalent accessible action. Owner assignment is not compliance: WP-NATIVE-01 closes its own findings and preserves feature-owned findings for their declared package.
5. Define exact compact/iPad/AX/real-locale/pseudo-long/RTL/contrast/motion scenario and artifact schemas that every visible package reruns on its own candidate head.
6. Add one project-owned filesystem-synchronized `ChapterFlowUITests/UpgradeEvidence` source group so
   later packages can create only their declared exact Swift test file without editing the Xcode
   project or sharing a broad UI-test write root.
7. Own and localize Share/Action capture, signed-out, pending, failure, and committed presentation in
   target-owned catalogs with at least one real non-English translation. Each target-local view owns
   the transaction-agnostic `ExtensionPresentationResultInput` with exactly `pending`, `committed`,
   and `failure(retryable)` presentation outcomes. A separate DEBUG/test-only initializer injects
   those states across locale, RTL, focus, announcement, non-color, motion/transparency, contrast,
   and target scenarios; production construction cannot select fixture state. Preserve the existing
   production initializer labels and void callback types for source compatibility, but make that
   legacy path fail closed: it never invokes the void capture/completion callback, enters committed
   or success, announces success, dismisses, or opens; it clears busy state, retains payload/note,
   leaves Cancel available, and exposes localized retry/error. Also expose a distinct production
   result-provider overload that accepts `ExtensionPresentationResultInput` without performing or
   interpreting a transaction. WP-EXT-01 alone supplies that provider and owns production durability,
   result mapping, success/failure proof, dismissal, and app opening.
8. Provide a deterministic paired iOS performance runner with one canonical fail-closed CLI. It
   verifies exact current-main/candidate worktrees and expected HEADs, builds current-main before
   candidate, consumes the selected structured budget ID, pins the budget-declared device classes,
   OS, toolchain, fixture, samples, and Hangs/SwiftUI templates, isolates DerivedData, and retains raw
   samples/xcresults/traces below one artifact directory. Its self-test parses and plans the complete
   Reader and Graph consumer fixtures and rejects missing, unknown, duplicate, relaxed, legacy, or
   cross-wired inputs; the runner never authors or relaxes a predeclared budget.

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

- Given deterministic Share/Action capture, signed-out, pending, error, and success presentation
  fixtures backed by each target-owned catalog
- When every declared real-locale, pseudo-long, plural/formatting, and RTL scenario actually executes
- Then localized meaning, logical action and reading order, semantic media direction, focus,
  announcements, and non-color status are preserved; each artifact records the executed inputs,
  `stateSource: fixture`, and `transactionClaim: none`, and claims no durable write, import,
  dismissal, or app-open ordering

- Given the existing Share/Action production initializer labels and void callback types plus the
  target-local `ExtensionPresentationResultInput` production result-provider overload
- When the legacy and fixture-boundary XCUITest runs against both extension targets
- Then existing controller construction compiles unchanged; the legacy Save/Ask path invokes no void
  capture/completion callback, never reaches committed/success or a success announcement, never
  dismisses/opens, clears busy state, retains payload/note, and offers localized retry/error plus
  Cancel; fixture injection is DEBUG/test-only and unreachable from production construction; and the
  typed production seam remains consumable by WP-EXT-01 without editing either view or catalog

### AC-NATIVE-01-05

- Given stable content and OS-dependent chrome/material surfaces
- When each surface is classified
- Then stable content uses deterministic comparison and unstable chrome uses named semantic/manual evidence without brittle thresholds

### AC-NATIVE-01-06

- Given every visible production string and interactive target, including Share and Action extensions
- When localization and target inventories run
- Then each item has a stable ID, owner package, evidence source, measurement status, and truthful
  compliance status; every WP-NATIVE-01-owned target is at least 44×44 points or has a validated
  28–43-point equivalent-access exception, while every out-of-package sub-44 or unverified target
  remains `owner-closure-required` and is never reported compliant

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
not change their outbox transaction semantics. Presentation-state names do not imply transaction
success. Until WP-EXT-01 integrates, NATIVE preserves the existing production initializer signature,
not its unsafe void-success behavior: the legacy capture path fails immediately and visibly without
invoking its void callback, retains recoverable input, clears busy state, and leaves Cancel available,
so the temporary degradation neither hangs nor silently loses data. The DEBUG/test-only fixture
initializer cannot be selected by production construction. WP-EXT-01 exclusively owns the
result-bearing writer/controller transition and all production durability, success, announcement,
dismissal, and app-open truth; NATIVE must stop before changing that transaction path.
Evidence contains no private content, identifiers, or tokens. Feature packages generate their own
candidate-head artifacts and close their assigned inventory; `reader-toolbar.depth-option` and
`reader-toolbar.tone-option` remain open for WP-READER-01 until its exact-head evidence closes them.
The synchronized UI-test group grants ownership only to each exact package-declared test file; later
packages never edit the project or another package's tests. iOS 18 retains the same user outcome as
enhanced APIs; there is no universal spacing-grid claim. Revert harness, project membership,
primitives, extension localization, metadata, and baselines together; never retain silent skips or
mass-approved baselines.

## Test plan and definition of done

Run every exact selector in [VALIDATE.md](VALIDATE.md), the full DesignSystem suite, native-evidence UI selectors, inventory schema checks, app build, independent exact-head review, required CI, merge verification, and safe cleanup. Missing runtime/manual evidence is blocked, not fabricated.
