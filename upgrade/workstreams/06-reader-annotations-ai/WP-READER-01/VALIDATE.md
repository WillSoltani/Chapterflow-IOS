# Validate WP-READER-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-READER-01-01 | READER-01-UNIT-01 | `swift test --package-path Packages/ReaderFeature --filter ReaderLoadOwnershipTests` | one reader owner publishes current chapter/tone/depth and late load cannot replace it | `results/reader/load-ownership.json` with candidate SHA and match/pass/skip counts |
| AC-READER-01-02 | READER-02-UNIT-01 | `swift test --package-path Packages/ReaderFeature --filter ReaderPreferenceIdentityTests` | repeated preference/progress changes retain one account/book/chapter-scoped authoritative state | `results/reader/preference-identity.json` |
| AC-READER-01-03 | READER-03-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-reader-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/reader/accessibility.xcresult -only-testing:ChapterFlowUITests/ReaderAccessibilityTests/testControlsTargetsOrderFocusAndAnnouncements -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | controls preserve 44-point default targets, logical order/focus, localized labels, and state announcements | `results/reader/accessibility.xcresult` |
| AC-READER-01-04 | READER-04-UNIT-01 | `swift test --package-path Packages/ReaderFeature --filter ReaderResumeTests` | background/relaunch restores exact position/context without duplicate progress/session events | `results/reader/resume.json` |
| AC-READER-01-05 | READER-05-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/ReaderNativeMatrixTests/testNavigationAndReadingMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-reader-matrix-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/reader/native-matrix` | every required dimension retains exact chapter navigation, localized content, semantics, and recovery | `results/reader/native-matrix/manifest.json` plus pinned iPhone and iPad `.xcresult` bundles plus scenario/accessibility report |
| AC-READER-01-05 | READER-05-PAGINATION-PERF-02 | `python3 scripts/visual/run_paired_performance.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --base <CURRENT_MAIN_SHA> --candidate <SHA> --test ChapterFlowUITests/ReaderPerformanceTests/testPaginationBudget --samples 30 --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --derived-data-root /private/tmp/Chapterflow-DD-reader-pagination-<SHA> --result-bundle-root results/reader/pagination-xcresults --instruments-template Hangs --budget-manifest upgrade/program/performance-budgets.json --budget-id PERF-READER-PAGINATION --output results/reader/pagination-performance.json` | current-main runs first; on identical device/OS/toolchain/fixture the candidate p95 and peak memory do not regress, stalls above 250 ms are zero, and exact destination identity remains correct for all 30 transitions per device class | `results/reader/pagination-performance.json` plus retained current-main/candidate `.xcresult` bundles, Hangs traces, raw samples, and budget digest |
| AC-READER-01-06 | READER-06-SWITCH-01 | `swift test --package-path Packages/ReaderFeature --filter ReaderAccountSwitchIsolationTests` | A chapter/variant/position/preferences/cache/events and in-flight tasks are cancelled or cleared and cannot render or commit for B; B uses only owner-matching state | `results/reader/account-switch-isolation.json` with A/sign-out/B sequence, owner keys, cancellation proof, and match/pass/skip counts |

Each selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Build/inherited native artifacts are supporting only.

## Supporting gates

- `swift test --package-path Packages/ReaderFeature --parallel`
- repository-standard unsigned Debug simulator build
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any stale publication, identity drift, duplicate event, inaccessible control, candidate mismatch, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
