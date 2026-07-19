# Validate WP-EXT-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-EXT-01-01 | EXT-01-HOST-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-ext-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/extensions/capture.xcresult -only-testing:ChapterFlowUITests/ExtensionCaptureHostTests/testSignedOutCaptureWritesBeforeSuccess -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | Share/Action host reports success only after a complete versioned durable write | `results/extensions/capture.xcresult` with nonzero match/pass/skip counts |
| AC-EXT-01-02 | EXT-02-UNIT-01 | `swift test --package-path Packages/AppFeature --filter ExtensionImportOrderTests` | authorized item is read→validated→attributed→imported→persisted→cleared exactly once under A | `results/extensions/import-order.json` with D-DATA-01 disposition |
| AC-EXT-01-03 | EXT-03-UNIT-01 | `swift test --package-path Packages/AppFeature --filter ExtensionImportRecoveryTests` | malformed/unknown/foreign/persistence-failed item remains recoverable/quarantined with no false success | `results/extensions/recovery.json` |
| AC-EXT-01-04 | EXT-04-UNIT-01 | `swift test --package-path Packages/AppFeature --filter ExtensionAccountIsolationTests` | B cannot see/claim/clear/import A or ownerless content without approved policy | `results/extensions/account-isolation.json` |
| AC-EXT-01-05 | EXT-05-INTEGRATION-01 | `swift test --package-path Packages/AppFeature --filter ExtensionTransactionBoundaryTests` | kill/restart injection at each boundary preserves recoverability and idempotency | `results/extensions/transaction-boundaries.json`; exact-final process scenario is deferred to WP-DEVICE-01 |
| AC-EXT-01-06 | EXT-06-OWNER-01 | `swift test --package-path Packages/Persistence --filter SharedSnapshotOwnershipTests` | model/writer require opaque owner and define publisher/reader conformance; missing/mismatched legacy snapshots quarantine | `results/extensions/shared-snapshot-owner.json` |
| AC-EXT-01-07 | EXT-07-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --derived-data /private/tmp/Chapterflow-DD-ext-<SHA> --test ChapterFlowUITests/ExtensionNativeMatrixTests/testCaptureAndRecoveryMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/extensions/native-matrix` | the inherited WP-NATIVE-01 Share/Action UI and real target-owned translations remain present while this package's capture/recovery truth, focus, announcements, and targets pass every required dimension | `results/extensions/native-matrix/manifest.json` plus iPhone/iPad `.xcresult` bundles and inherited target/catalog accessibility report |

Every selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Final App Group/process-boundary evidence runs as `DEVICE-APNS-WIDGET-EXTENSION-ROUTING`.

## Supporting gates

- full Persistence and AppFeature extension-import suites plus extension-host build/tests
- repository-standard unsigned app/extension build
- schema/migration/account-isolation proof, candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Unresolved D-DATA-01, import-before-persist/clear, false success, data loss, cross-account claim, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
