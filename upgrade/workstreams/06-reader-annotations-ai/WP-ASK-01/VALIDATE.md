# Validate WP-ASK-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-ASK-01-01 | ASK-01-NETWORK-01 | `swift test --package-path Packages/Networking --filter AskContractTests` | canonical history/SSE frames/errors/terminal event decode and old JSON assumption is rejected | `results/ask/network-contract.json` with candidate SHA and selector match/pass/skip counts |
| AC-ASK-01-01 | ASK-01-FEATURE-01 | `swift test --package-path Packages/AIFeature --filter AskCanonicalTransportTests` | Ask state consumes the canonical transport without reintroducing the old JSON assumption | `results/ask/feature-transport.json` with candidate SHA and selector match/pass/skip counts |
| AC-ASK-01-02 | ASK-02-UNIT-01 | `swift test --package-path Packages/AIFeature --filter AskStreamLifetimeTests` | superseded/closed stream cannot publish text, citations, quota, or error | `results/ask/stream-lifetime.json` |
| AC-ASK-01-03 | ASK-03-UNIT-01 | `swift test --package-path Packages/AIFeature --filter CitationValidationTests` | valid citation routes exact book/chapter/source; invalid bounds/identity remains non-navigable | `results/ask/citations.json` |
| AC-ASK-01-04 | ASK-04-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-ask-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/ask/states.xcresult -only-testing:ChapterFlowUITests/AskStateTests/testOfflineQuotaModerationInterruptedAndOnDeviceStates -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | each state is distinct/truthful and safely preserves question/context | `results/ask/states.xcresult` |
| AC-ASK-01-05 | ASK-05-PRIVACY-01 | `swift test --package-path Packages/AIFeature --filter AskPrivacyTests` | log/analytics/evidence spies contain no question, selection, answer, citation text, auth, URL, or private ID | `results/ask/privacy.json` |
| AC-ASK-01-06 | ASK-06-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/AskNativeMatrixTests/testAdaptiveLocalizedAccessibleMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-ask-matrix-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/ask/native-matrix` | every required dimension preserves question, localized actions, reading order, focus, and targets | `results/ask/native-matrix/manifest.json` plus pinned iPhone and iPad `.xcresult` bundles plus scenario/accessibility report |
| AC-ASK-01-07 | ASK-07-UNIT-01 | `swift test --package-path Packages/AIFeature --filter AskAccountIsolationTests` | account A stream/cache/question/selection/answer/citation/retry state is absent after sign-out and cannot appear for B | `results/ask/account-isolation.json` |

Every selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Broad suites/builds are supporting only.

## Supporting gates

- full AIFeature, Networking, and affected ReaderFeature suites
- repository-standard unsigned Debug simulator build
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any transport ambiguity, private-data leak, invalid route, stale publication, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
