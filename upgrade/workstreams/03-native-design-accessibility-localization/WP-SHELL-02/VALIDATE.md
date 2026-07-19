# Validate WP-SHELL-02

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-SHELL-02-01 | SHELL-01-UNIT-01 | `swift test --package-path Packages/AppFeature --filter AppShellTopologyTests` | approved top-level roles are unique and every feature route has one composition site | `results/shell/topology.json` with D-IA decision ID, candidate SHA, and match/pass/skip counts |
| AC-SHELL-02-02 | SHELL-02-UNIT-01 | `swift test --package-path Packages/AppFeature --filter AppShellExactRouteTests` | Discover/Detail/reader/settings/external typed routes and auth replay open exactly once without tab fallback | `results/shell/routes.json` |
| AC-SHELL-02-03 | SHELL-03-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-shell-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/shell/session-transitions.xcresult -only-testing:ChapterFlowUITests/AppShellTests/testSessionTransitionsNeverFlashPrivateContent -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | all session transitions retain singular owners and A→B never exposes A | `results/shell/session-transitions.xcresult` |
| AC-SHELL-02-04 | SHELL-04-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/AppShellTests/testCompactIPadKeyboardAndRuntimeOutcomeMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-shell-matrix-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/shell/native-matrix` | every required dimension preserves route, focus, localized content, safe areas, and runtime outcome | `results/shell/native-matrix/manifest.json` plus pinned iPhone and iPad `.xcresult` bundles plus scenario manifest/accessibility report |

Every selector requires `matched >= 1`, `failed = 0`, `skipped = 0`, and no disabled/known-issue waiver. Builds and inherited NATIVE artifacts are supporting evidence; this package must produce candidate-head shell evidence.

## Supporting gates

- `swift test --package-path Packages/AppFeature --parallel`
- repository-standard unsigned Debug simulator build
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Unresolved D-IA-01, route duplication/loss, candidate mismatch, missing native scenario, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
