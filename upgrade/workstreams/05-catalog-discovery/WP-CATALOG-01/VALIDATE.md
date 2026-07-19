# Validate WP-CATALOG-01

Record every command/scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required
selector passes only with `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matches, disabled tests,
and known-issue waivers fail.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-CATALOG-01-01 | CATALOG-01-UNIT-01 | `swift test --package-path Packages/LibraryFeature --filter CatalogPartialStateTests` | empty/partial/failure states are intentional and preserve usable cached/independent content | `results/catalog/partial-state.json` with candidate SHA and nonzero match/pass/skip counts |
| AC-CATALOG-01-02 | CATALOG-02-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-catalog-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/catalog/controls.xcresult -only-testing:ChapterFlowUITests/CatalogControlTests/testSelectionSaveAndRemoveAreSeparateControls -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | selection/save/remove have separate hit regions, focus order, labels, and activation | `results/catalog/controls.xcresult` |
| AC-CATALOG-01-03 | CATALOG-03-UNIT-01 | `swift test --package-path Packages/LibraryFeature --filter SearchCancellationTests` | late A cannot replace B; cancellation is silent and produces no stale analytics | `results/catalog/search-cancellation.json` |
| AC-CATALOG-01-04 | CATALOG-04-UNIT-01 | `swift test --package-path Packages/LibraryFeature --filter DiscoverRouteTests` | selection emits one typed exact-book feature route and no tab-only destination | `results/catalog/discover-route.json` |
| AC-CATALOG-01-05 | CATALOG-05-UNIT-01 | `swift test --package-path Packages/LibraryFeature --filter BookDetailPartialStateTests` | cover/section failure preserves metadata and scopes retry | `results/catalog/detail-partial.json` |
| AC-CATALOG-01-06 | CATALOG-06-UNIT-01 | `swift test --package-path Packages/LibraryFeature --filter BookDetailStartContinueLifecycleTests` | repeated/superseded/offline/auth/background/relaunch emits one authoritative exact route and no unlock | `results/catalog/start-continue-lifecycle.json` |
| AC-CATALOG-01-07 | CATALOG-07-UNIT-01 | `swift test --package-path Packages/LibraryFeature --filter CatalogAccountIsolationTests` | A state/work cannot publish into B and public state remains explicit | `results/catalog/account-isolation.json` |
| AC-CATALOG-01-08 | CATALOG-08-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --derived-data /private/tmp/Chapterflow-DD-catalog-<SHA> --test ChapterFlowUITests/CatalogToDetailNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/catalog/native-matrix` | every required dimension and real translated value preserves hierarchy/actions/focus/announcements/targets and exact routes | `results/catalog/native-matrix/manifest.json` plus pinned iPhone/iPad `.xcresult` bundles and catalog/accessibility report |

## Supporting gates

- `swift test --package-path Packages/LibraryFeature --parallel`
- affected AppFeature route tests and repository-standard unsigned Debug simulator build
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI,
  merge ancestry, and post-merge CI

Any cache loss, cross-account leak, nested/dead control, stale result, route identity loss, local
authority grant, missing native/localization dimension, failed/skipped selector, or unresolved
P0/P1/P2 blocks merge.
