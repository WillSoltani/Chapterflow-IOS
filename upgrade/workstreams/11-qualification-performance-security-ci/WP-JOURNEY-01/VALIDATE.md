# Validate WP-JOURNEY-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-JOURNEY-01-01 | JOURNEY-01-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-journey-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/journey/central-loop.xcresult -only-testing:ChapterFlowUITests/CentralJourneyTests/testDiscoverDetailReadListenAnnotateAskQuizResume -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | every exact transition fires once; server/account authority and exact resume identity remain | `results/journey/central-loop.xcresult` with candidate SHA and nonzero match/pass/skip counts |
| AC-JOURNEY-01-02 | JOURNEY-02-MANIFEST-01 | `python3 scripts/qa/simulator/run_scenarios.py --manifest scripts/qa/simulator/scenarios.json --suite adverse --candidate <SHA> --output results/journey/adverse.json` | all required stable IDs cover declared adverse states with zero duplicate mutation/cross-account exposure | `results/journey/adverse.json` plus fixture/manifest digests |
| AC-JOURNEY-01-03 | JOURNEY-03-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/JourneyNativeMatrixTests/testLightDarkCompactIPadAXLocalizationAccessibility --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-journey-matrix-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/journey/native-matrix` | candidate-head matrix preserves required localized content, actions, and focus across every required dimension | `results/journey/native-matrix/manifest.json` plus pinned iPhone and iPad `.xcresult` bundles plus scenario/accessibility report |

Every selector/scenario requires `matched >= 1`, `failed = 0`, `skipped = 0`, and no disabled/known-issue waiver. A build, screenshot, broad suite, or Maestro-only result cannot satisfy an AC.

## Delivery and post-merge evidence

After every AC, independent review, and exact-head required check passes, run
`python3 scripts/qa/simulator/verify_candidate.py --candidate <SHA> --results results/journey --require-review --require-ci --require-merge --require-post-merge-ci --output results/journey/candidate.json`.
The required artifact is `results/journey/candidate.json` plus exact PR-head, check/run, merge, target,
and post-merge CI identifiers. This evidence cannot satisfy a pre-merge AC or authorize release.

## Supporting gates

- repository-standard unsigned Debug simulator build
- full deterministic `ChapterFlowUITests` lane with `-parallel-testing-enabled NO`
- optional Maestro only for distinct black-box evidence, never as a replacement
- candidate-head intended-path/secret scan, `git diff --check`, independent exact-head review, required CI, merge ancestry, and post-merge CI

Any fixture authority leak, missing scenario ID, cross-account exposure, candidate/reviewer/CI mismatch, failed/skipped selector, unresolved P0/P1/P2, or attempted device/release claim blocks merge.
