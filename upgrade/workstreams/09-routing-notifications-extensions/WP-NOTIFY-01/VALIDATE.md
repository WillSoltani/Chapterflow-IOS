# Validate WP-NOTIFY-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-NOTIFY-01-01 | NOTIFY-01-UNIT-01 | `swift test --package-path Packages/NotificationsFeature --filter RegistrationTruthTests` | failed register/unregister remains pending and unacknowledged; safe reconnect retries exactly once | `results/notify/registration.json` with candidate SHA and match/pass/skip counts |
| AC-NOTIFY-01-02 | NOTIFY-02-UNIT-01 | `swift test --package-path Packages/NotificationsFeature --filter SnapshotOwnershipTests` | missing/mismatched owner models render no private content and invent no owner | `results/notify/widget-ownership.json` with candidate SHA and match/pass/skip counts |
| AC-NOTIFY-01-03 | NOTIFY-03-UNIT-01 | `swift test --package-path Packages/AppFeature --filter ExternalDestinationReplayTests` | full book/chapter/review/other typed destination replays exactly once after auth, not tab-only | `results/notify/exact-routing.json` |
| AC-NOTIFY-01-04 | NOTIFY-04-UNIT-01 | `swift test --package-path Packages/NotificationsFeature --filter NotificationDispatchSafetyTests` | unknown/malformed payload mutates nothing and logs only fixed privacy-safe fields | `results/notify/unknown-payload.json` |
| AC-NOTIFY-01-05 | NOTIFY-05-INTEGRATION-01 | `swift test --package-path Packages/NotificationsFeature --filter NotificationAccountLifecycleTests` | permission/token/background/A→B deterministic model preserves exact owner/retry/cleanup | `results/notify/account-lifecycle.json`; exact-final device scenario is deferred to WP-DEVICE-01 |
| AC-NOTIFY-01-06 | NOTIFY-06-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --derived-data /private/tmp/Chapterflow-DD-notify-<SHA> --test ChapterFlowUITests/NotificationWidgetNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/notify/native-matrix` | every required dimension and real translation preserves settings/retry/widget/activity/routing content, focus, announcements, and targets | `results/notify/native-matrix/manifest.json` plus iPhone/iPad `.xcresult` bundles and catalog/accessibility report |

Every selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Final APNs/widget/Live Activity/background behavior runs as `DEVICE-APNS-WIDGET-EXTENSION-ROUTING`.

## Supporting gates

- full NotificationsFeature and affected AppFeature/widget suites
- repository-standard unsigned app/widget/extension build
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any premature acknowledgement, private snapshot exposure, route identity loss, unsafe unknown payload, cross-account state, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
