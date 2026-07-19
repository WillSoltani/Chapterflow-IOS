# Validate WP-AUDIO-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-AUDIO-01-01 | AUDIO-01-CONTRACT-01 | `swift test --package-path Packages/Networking --filter AudioContractTests` | raw plan/discriminator and segment evolution policy match canonical source; invented envelope is rejected | `results/audio/contract.json` with candidate SHA and match/pass/skip counts |
| AC-AUDIO-01-02 | AUDIO-02-UNIT-01 | `swift test --package-path Packages/AIFeature --filter AudioSessionBoundaryTests` | late chapter-A work cannot replace chapter-B queue/artwork/position/error | `results/audio/session-boundary.json` |
| AC-AUDIO-01-03 | AUDIO-03-UNIT-01 | `swift test --package-path Packages/AIFeature --filter AudioLifecycleStateTests` | deterministic interruption/route/background/expired-URL events reconcile truthfully and text remains usable | `results/audio/lifecycle-state.json`; final device scenario remains `DEVICE-AUDIO-NETWORK-STORAGE-LIFECYCLE` |
| AC-AUDIO-01-04 | AUDIO-04-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-audio-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/audio/reader-listen.xcresult -only-testing:ChapterFlowUITests/ReaderListenTests/testExactIdentityAndSingleMediaOwner -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | Listen preserves book/chapter/segment/position identity and one media owner | `results/audio/reader-listen.xcresult` |
| AC-AUDIO-01-05 | AUDIO-05-UNIT-01 | `swift test --package-path Packages/AIFeature --filter AudioQualificationInstrumentationTests` | metrics/scenario hooks bind revision, redact private values, do not alter behavior, and expose all DEVICE-required fields | `results/audio/instrumentation.json` plus schema digest |
| AC-AUDIO-01-06 | AUDIO-06-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/AudioNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-audio-matrix-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/audio/native-matrix` | every required dimension preserves localized playback content, controls, focus, semantics, status, and targets | `results/audio/native-matrix/manifest.json` plus pinned iPhone/iPad `.xcresult` bundles and catalog/accessibility report |
| AC-AUDIO-01-07 | AUDIO-07-UNIT-01 | `swift test --package-path Packages/AIFeature --filter AudioAccountIsolationTests` | account A queue/position/artwork/route/error/download/plan state is cancelled and absent for account B | `results/audio/account-isolation.json` |

Each selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Simulator state tests do not satisfy final physical-device/performance qualification.

## Supporting gates

- full Networking, AIFeature, and affected ReaderFeature suites
- repository-standard unsigned Debug simulator build
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any invented contract, second media owner, stale publication, text fallback loss, privacy leak, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
