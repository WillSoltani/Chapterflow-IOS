# Validate WP-ENTRY-01

Record every command/scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. Required
selectors pass only with `matched >= 1`, `failed = 0`, `skipped = 0`; no disabled/known-issue waiver.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-ENTRY-01-01 | ENTRY-01-UNIT-01 | `swift test --package-path Packages/OnboardingFeature --filter OnboardingRecoveryTests` | interruption/background/relaunch restores one durable current step without duplicate completion | `results/entry/recovery.json` with candidate SHA and nonzero match/pass/skip counts |
| AC-ENTRY-01-02 | ENTRY-02-UNIT-01 | `swift test --package-path Packages/OnboardingFeature --filter PermissionTruthTests` | denied/restricted/unavailable/changed states remain truthful and recoverable | `results/entry/permissions.json` |
| AC-ENTRY-01-03 | ENTRY-03-UNIT-01 | `swift test --package-path Packages/OnboardingFeature --filter OnboardingAccountOperationLifetimeTests` | stale/repeated/A→B work cannot publish and telemetry is privacy-safe | `results/entry/account-lifetime.json` |
| AC-ENTRY-01-04 | ENTRY-04-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --derived-data /private/tmp/Chapterflow-DD-entry-<SHA> --test ChapterFlowUITests/OnboardingNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/entry/native-matrix` | every required dimension and real translation preserves content/actions/focus/announcements/targets | `results/entry/native-matrix/manifest.json` plus iPhone/iPad `.xcresult` bundles and catalog/accessibility report |

## Supporting gates

- `swift test --package-path Packages/OnboardingFeature --parallel`
- dependent AppFeature tests and repository-standard unsigned Debug simulator build
- intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and
  post-merge CI

Any state loss, false permission, cross-account publication, missing native/localization dimension,
failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
