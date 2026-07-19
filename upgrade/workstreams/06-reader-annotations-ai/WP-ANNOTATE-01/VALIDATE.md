# Validate WP-ANNOTATE-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-ANNOTATE-01-01 | ANNOTATE-01-CONTRACT-01 | `swift test --package-path Packages/Networking --filter AnnotationContractTests` | canonical supported capability/alias shape is source-derived and absent operations remain unavailable | `results/annotate/contract.json` with candidate SHA and match/pass/skip counts |
| AC-ANNOTATE-01-02 | ANNOTATE-02-UNIT-01 | `swift test --package-path Packages/Persistence --filter AnnotationJournalDurabilityTests` | offline mutation survives relaunch with complete versioned payload/stable ID and submits once | `results/annotate/durability.json` |
| AC-ANNOTATE-01-03 | ANNOTATE-03-UNIT-01 | `swift test --package-path Packages/Persistence --filter AnnotationQuarantineTests` | malformed/unknown/uncertain work is retained or quarantined, never deleted as successful no-op | `results/annotate/quarantine.json` |
| AC-ANNOTATE-01-04 | ANNOTATE-04-UNIT-01 | `swift test --package-path Packages/Persistence --filter AnnotationAccountIsolationTests` | account B cannot read or drain account-A note/highlight/bookmark work | `results/annotate/account-isolation.json` |
| AC-ANNOTATE-01-05 | ANNOTATE-05-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-annotate-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/annotate/recovery.xcresult -only-testing:ChapterFlowUITests/AnnotationRecoveryTests/testQueuedSyncFailedConflictAndAuthExpiry -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | UI distinguishes queued/syncing/failed/synced/conflict/auth recovery and preserves context | `results/annotate/recovery.xcresult` plus accessibility report |
| AC-ANNOTATE-01-06 | ANNOTATE-06-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --derived-data /private/tmp/Chapterflow-DD-annotate-<SHA> --test ChapterFlowUITests/AnnotationNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/annotate/native-matrix` | every dimension and real translation preserves private-content status, focus, announcements, targets, and recovery | `results/annotate/native-matrix/manifest.json` plus iPhone/iPad `.xcresult` bundles and catalog/accessibility report |

Each selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Private annotation content must not enter logs/artifacts.

## Supporting gates

- full ReaderFeature, Networking, and Persistence suites
- repository-standard unsigned Debug simulator build
- migration/account-isolation proof, candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any silent mutation loss, invented contract, cross-account access, false sync state, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
