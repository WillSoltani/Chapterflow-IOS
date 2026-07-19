# Validate WP-OFFLINE-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-OFFLINE-01-01 | OFFLINE-01-UNIT-01 | `swift test --package-path Packages/SyncEngine --filter DownloadResumeTests` | relaunch resumes only missing validated assets and never marks completion early | `results/offline/download-resume.json` with candidate SHA and match/pass/skip counts |
| AC-OFFLINE-01-02 | OFFLINE-02-UNIT-01 | `swift test --package-path Packages/Persistence --filter StorageReconciliationTests` | corruption/expiry/low storage yields correct accounting/action and preserves unrelated/text data | `results/offline/storage-reconciliation.json` |
| AC-OFFLINE-01-03 | OFFLINE-03-UNIT-01 | `swift test --package-path Packages/SyncEngine --filter OutboxQuarantineTests` | unknown/malformed/uncertain mutation is retained/quarantined, never successful no-op | `results/offline/outbox-quarantine.json` |
| AC-OFFLINE-01-04 | OFFLINE-04-UNIT-01 | `swift test --package-path Packages/SyncEngine --filter AccountBoundaryTests` | auth expiry/sign-out quiesces A before B; B cannot see/delete/drain A | `results/offline/account-boundary.json` |
| AC-OFFLINE-01-05 | OFFLINE-05-INTEGRATION-01 | `swift test --package-path Packages/SyncEngine --filter ConnectivityRecoveryTests` | deterministic offline→online preserves order/idempotency and distinguishes cache from fresh sync | `results/offline/connectivity-recovery.json`; final real-network scenario is deferred to WP-DEVICE-01 |
| AC-OFFLINE-01-06 | OFFLINE-06-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/OfflineNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-offline-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/offline/native-matrix` | every required dimension preserves localized download/sync/storage truth, actions, focus, semantics, and targets | `results/offline/native-matrix/manifest.json` plus pinned iPhone/iPad `.xcresult` bundles and catalog/accessibility report |

Each selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Final real-network/storage/background/memory evidence runs as `DEVICE-AUDIO-NETWORK-STORAGE-LIFECYCLE` on the exact candidate.

## Supporting gates

- full SyncEngine, Persistence, and affected LibraryFeature suites
- repository-standard unsigned Debug simulator build
- migration/account-isolation proof, candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any premature completion, unrelated deletion, silent mutation loss, cross-account access, stale/cached-as-fresh state, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
