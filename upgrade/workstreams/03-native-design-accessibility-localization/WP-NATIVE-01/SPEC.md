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
8. Replace exactly `scripts/localization/scenarios.json` with the single shared DEBUG evidence source
   `scripts/localization/NativeExtensionEvidenceHost.swift`, keeping the exact 20-file manifest and
   every existing root/allocation. Move the complete former localization envelope, schemas, fixtures,
   and scenarios under `scripts/visual/native-matrix.json#localizationMatrix`; the retained validator
   consumes it with `--manifest-key localizationMatrix`, while the distinct runtime matrix remains the
   authority for actual target execution. Add the host as one explicit file reference and exactly one
   source-phase entry in each extension target, never the main app or UI-test bundle. Per-file
   conditions are `CF_NATIVE_SHARE_EVIDENCE_TARGET` and `CF_NATIVE_ACTION_EVIDENCE_TARGET`.
   Ordinary Debug and Release builds exclude the host. The evidence build is Debug-only, requires
   `CF_NATIVE_EXTENSION_EVIDENCE_BUILD`, and uses `EXCLUDED_SOURCE_FILE_NAMES` through
   `CF_NATIVE_EXTENSION_EXCLUDED_SOURCES` to exclude `ShareViewController.swift` and
   `ActionViewController.swift`. The host supplies those unchanged principal class names, parses a
   versioned privacy-safe system-host fixture token, and instantiates the actual target-local DEBUG
   seam. The existing controllers and Info.plists remain read-only.
9. Invoke the installed `ShareExtension.appex` and `ActionExtension.appex` through a real
   containing/system host and system extension UI. Bind the observed extension bundle/process,
   scenario token, target-owned view hierarchy, candidate head, and artifact digests. Source scanning,
   importing extension views into the main app or UI-test bundle, direct `.appex` launch, hardcoded
   markers, or static fixture claims do not satisfy runtime evidence. Action-extension discovery and
   invocation must pass on the pinned simulator; nondeterministic discovery is a blocker, not a skip.
   System-trait evidence and fixture-behavior evidence are separate. Automated real-extension records
   use `inputSource=system` and record the public system-derived `colorSchemeContrast`,
   `accessibilityReduceMotion`, and `accessibilityReduceTransparency` values observed inside the
   extension process. They may claim a requested system state only when that observation matches the
   request and an independent rendered consequence is verified. A preconfigured simulator/device that
   does not report the requested value fails that scenario; it is never passed or skipped. Deterministic
   behavior fixtures use `inputSource=fixture` and `systemTraitClaim=none`; they exercise rendering
   branches but do not qualify a system setting.
10. Provide a deterministic paired iOS performance runner with one canonical fail-closed CLI. It
   verifies exact current-main/candidate worktrees and expected HEADs, builds current-main before
   candidate, consumes the selected structured budget ID, pins the budget-declared device classes,
   OS, toolchain, fixture, samples, and Hangs/SwiftUI templates, isolates DerivedData, and retains raw
   samples/xcresults/traces below one artifact directory. Its self-test parses and plans the complete
   Reader and Graph consumer fixtures and rejects missing, unknown, duplicate, relaxed, legacy, or
   cross-wired inputs; the runner never authors or relaxes a predeclared budget.
11. Add one fail-closed `--self-test` mode inside the existing `scripts/visual/touch_targets.py`; do
    not add a dedicated test file. The literal command is
    `python3 scripts/visual/touch_targets.py --self-test --output results/native/touch-target-scanner-regressions.json`.
    Every named case constructs a deterministic source fixture and calls the same production scanner
    seam used by `--check`, never duplicated parsing or condition logic. The reviewed registry and
    executed case set must be identical and unique, with exactly `matched=20`, `passed=20`,
    `failed=0`, and `skipped=0`. Missing, duplicate, silently unexecuted, altered, skipped, or
    expectation-drifted cases fail the command.
12. Resume exactly one correction cycle against reviewed candidate
    `39843e6d6a0e3468f61ed86f180500bdb7529c44` / tree
    `9afbb87bb859ead2dad46f180da2911e119e62c3`. The package claim remains with WP-NATIVE-01;
    `xcode-project` and `simulator-device` were released and must be reacquired before their next use.
    The correction may edit only the five reviewed runtime files plus
    `scripts/visual/native-matrix.json`: `ActionExtension/ActionView.swift`,
    `ShareExtension/ShareView.swift`,
    `ChapterFlowUITests/UpgradeEvidence/NativeUpgradeEvidenceTests.swift`,
    `scripts/localization/NativeExtensionEvidenceHost.swift`,
    `scripts/visual/run_native_matrix.py`, and `scripts/visual/native-matrix.json`. These six paths are
    already members of the exact 20-path candidate manifest; the 20-file/three-root cap, dependency DAG,
    existing locks, WP-EXT-01 transaction ownership, and every release boundary remain unchanged.
13. Automate only observable semantics: discover named system extension elements and select installed
    extension display names, then verify labels, values, traits, order, focus, geometry, and rendered
    state. Spoken VoiceOver output, pointer behavior, and system preconfiguration are explicit manual or
    preconfigured-system evidence and cannot be self-attested. Coordinate-only activity selection and
    copied planned assertions are not evidence.
14. Emit exactly 62 full-matrix records: 15 compact-iPhone and 16 regular-iPad records for each of Share
    and Action. Every record resets token-scoped observers, binds exact payload and configuration
    digests, and binds the extension process, executable, and Info.plist identities. Localization,
    pseudo-long, RTL, plural, formatting, and accessibility results contain observed rendered/semantic
    consequences, not repeated plan inputs. The full-matrix artifact contains exactly two xcresults,
    one for the pinned iPhone and one for the pinned iPad.
15. Bind the four runtime stages to one attempt-chain ID and attempt number one. Build-boundary creates
    stage one only when the chain and output are absent; each later stage requires and hashes the exact
    successful predecessor manifest. Existing stage output, a different chain/candidate/configuration,
    an out-of-order stage, or any second attempt fails without overwrite. Production-boundary runs
    through the existing native-matrix runner, compares the nonzero exact candidate to `git rev-parse
    HEAD`, and executes missing, all-zero, malformed, and mismatched candidate negative cases before
    the valid case. The full matrix repeats the named-system-element and installed-display-name gates.

### Touch-target scanner regression registry

The exact 20 reviewed named cases are: `direct-button`, `direct-non-button`, `trailing-frame`,
`multiline-frame`, `label-frame`, `self-constant`, `designsystem-constant`, `partial-dimensions`,
`sibling-frame-non-borrowing`, `nested-frame-non-borrowing`, `line-comments-ignored`,
`block-comments-ignored`, `ordinary-strings-ignored`, `multiline-strings-ignored`,
`previews-ignored`, `inactive-debug-ignored`, `active-ios-conditions`,
`elseif-else-fail-closed`, `valid-adjacent-exception`, and `invalid-exception-forms`. The final case
covers malformed, commented, string-contained, and nonadjacent exception markers. These scanner
regressions do not close `reader-toolbar.depth-option` or `reader-toolbar.tone-option`; both remain
WP-READER-01 owner closures.

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

- Given the guarded extension evidence build
- When its containing app is installed and the Share and Action extensions are selected through a
  containing/system host's system UI
- Then each real `.appex` runs its target-specific evidence principal controller, instantiates the
  actual target-local DEBUG fixture seam, and emits exact-head presentation/localization/accessibility
  evidence with `stateSource=fixture` and `transactionClaim=none`; the evidence build excludes both
  production controllers, while ordinary Debug and Release builds exclude the evidence host and
  include those controllers under the unchanged Info.plists

- Given a requested contrast, Reduce Motion, or Reduce Transparency system setting
- When a real Share or Action extension record executes
- Then the artifact distinguishes `inputSource=system` from `inputSource=fixture`; reports the actual
  extension-process value for `colorSchemeContrast`, `accessibilityReduceMotion`, and
  `accessibilityReduceTransparency`; claims the requested state only after a matching observation and
  independently observed rendered consequence; and fails rather than passes/skips on mismatch, while
  fixture records state `systemTraitClaim=none`

- Given the full Share/Action correction matrix
- When runtime evidence executes after a clear static review
- Then build-boundary runs first, one representative Share record and one representative Action record
  run second, production-boundary runs third with a required nonzero exact candidate SHA, and the full
  62-record matrix runs last; the first deterministic mismatch stops execution without retry-based
  greening; every stage is attempt one in the same predecessor-digest chain and refuses existing output;
  and the final matrix retains exactly two xcresults

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

- Given the exact reviewed 20-case touch-target scanner registry
- When the scanner's in-file self-test runs through the production scanner seam
- Then all 20 unique named cases execute with `matched=20`, `passed=20`, `failed=0`, and `skipped=0`,
  and registry, execution, or expectation drift fails closed without changing Reader owner closures

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
initializer cannot be selected by production construction. The shared evidence host belongs only to
the two extension source phases, is excluded from ordinary Debug and Release, and compiles only with
`DEBUG`, `CF_NATIVE_EXTENSION_EVIDENCE_BUILD`, and exactly one target flag. Evidence builds exclude
the production controllers without changing them or either Info.plist; malformed flag/source
combinations fail project validation or compilation before runtime. WP-EXT-01 exclusively owns the
result-bearing writer/controller transition and all production durability, success, announcement,
dismissal, and app-open truth; NATIVE must stop before changing that transaction path.
Evidence contains no private content, identifiers, or tokens. Feature packages generate their own
candidate-head artifacts and close their assigned inventory; `reader-toolbar.depth-option` and
`reader-toolbar.tone-option` remain open for WP-READER-01 until its exact-head evidence closes them.
The synchronized UI-test group grants ownership only to each exact package-declared test file; later
packages never edit the project or another package's tests. iOS 18 retains the same user outcome as
enhanced APIs; there is no universal spacing-grid claim. Revert harness, project membership,
primitives, extension localization, metadata, and baselines together. The path exchange rolls back
atomically: remove the evidence-host membership/source, restore the standalone localization scenario
file and validator input, and restore the before manifest. Never retain a partial source/oracle swap,
silent skips, or mass-approved baselines.

## Platform authority

Apple defines an app extension as a separate process whose lifecycle begins when a person selects it
through a host app's UI, and directs XCTest-based extension tests to use the containing app as the
host environment. The evidence host therefore changes only the DEBUG extension entry controller and
still requires real host-mediated `.appex` invocation; direct executable launch or source import is
not equivalent. See [Understand How an App Extension Works](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html),
[Creating an App Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html),
and [Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project).

SwiftUI's `colorSchemeContrast`, `accessibilityReduceMotion`, and
`accessibilityReduceTransparency` environment values are get-only system preferences. Public APIs do
not let the extension set them. Explicit view behavior inputs therefore cannot prove an OS setting.

## Test plan and definition of done

Run every exact selector in [VALIDATE.md](VALIDATE.md), the full DesignSystem suite, native-evidence UI selectors, inventory schema checks, app build, independent exact-head review, required CI, merge verification, and safe cleanup. After a clear static review, execute build-boundary, representative Share+Action, production-boundary, and the full 62-record matrix in that order. Missing runtime/manual/system-preconfiguration evidence is failed or blocked as declared, never fabricated, self-attested, passed, or skipped.
