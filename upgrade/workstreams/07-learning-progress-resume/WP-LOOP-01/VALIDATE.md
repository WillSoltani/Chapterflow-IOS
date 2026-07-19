# Validate WP-LOOP-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-LOOP-01-01 | LOOP-01-UNIT-01 | `swift test --package-path Packages/AppFeature --filter LearningLoopReachabilityTests` | Detail/Start/Continue/Reader/Listen/annotation/Ask/quiz/review are reachable in one exact context | `results/loop/reachability.json` with candidate SHA and match/pass/skip counts |
| AC-LOOP-01-02 | LOOP-02-UNIT-01 | `swift test --package-path Packages/AppFeature --filter LearningLoopAuthorityTests` | accepted authority refreshes progress/next state once and no local unlock/reward is synthesized | `results/loop/authority.json` |
| AC-LOOP-01-03 | LOOP-03-UNIT-01 | `swift test --package-path Packages/AppFeature --filter LearningLoopResumeTests` | background/termination/auth interruption restores exact book/chapter/variant/position/action once | `results/loop/resume.json` |
| AC-LOOP-01-04 | LOOP-04-UNIT-01 | `swift test --package-path Packages/AppFeature --filter LearningLoopDuplicateSuppressionTests` | stale/repeated callback cannot duplicate route, sheet, event, write, or completion | `results/loop/duplicate-suppression.json` |
| AC-LOOP-01-05 | LOOP-05-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-loop-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/loop/account-switch.xcresult -only-testing:ChapterFlowUITests/LearningLoopTests/testAccountSwitchCannotResumePreviousAccount -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | account B cannot observe/resume A and A work is stopped or retained safely | `results/loop/account-switch.xcresult` |
| AC-LOOP-01-06 | LOOP-06-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/LearningLoopNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-loop-matrix-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/loop/native-matrix` | every required dimension preserves localized content/actions, exact routes, focus, semantics, and comfortable targets | `results/loop/native-matrix/manifest.json` plus pinned iPhone/iPad `.xcresult` bundles and catalog/accessibility report |

Each selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. A build or broad dependent suite alone cannot satisfy an AC.

## Supporting gates

- full AppFeature plus affected Library/Reader/AI/Quiz/Engagement/Sync package suites
- repository-standard unsigned Debug simulator build and focused loop UI smoke
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any unreachable loop action, local authority, duplicate transition, exact-resume loss, cross-account exposure, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
