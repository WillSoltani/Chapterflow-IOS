# Validate WP-AUTH-02

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-AUTH-02-01 | AUTH-01-CONFIG-01 | `swift test --package-path Packages/AuthKit --filter KeychainEntitlementSourceContractTests` | app, Share, Action, and widget entitlement sources/build-setting fixtures declare one approved least-privilege group | `results/auth/entitlement-sources.json` with candidate SHA, target list, and nonzero match/pass/skip counts |
| AC-AUTH-02-01 | AUTH-01-PERSIST-02 | `swift test --package-path Packages/Persistence --filter KeychainAccessGroupContractTests` | every production Keychain query uses the declared group and missing entitlement fails closed | `results/auth/keychain-queries.json` |
| AC-AUTH-02-02 | AUTH-02-UNIT-01 | `swift test --package-path Packages/AuthKit --filter SessionLifecycleTests` | relaunch restores same identity and sign-out quiesces account work before teardown | `results/auth/session-lifecycle.json` with match/pass/skip counts |
| AC-AUTH-02-03 | AUTH-03-UNIT-01 | `swift test --package-path Packages/AuthKit --filter SessionIsolationTests` | account B observes no account-A token, task, data, or entitlement | `results/auth/account-isolation.json` |
| AC-AUTH-02-04 | AUTH-04-UI-01 | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-auth-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/auth/reauth.xcresult -only-testing:ChapterFlowUITests/ReauthTests/testSuccessCancelOfflineAndExpiredVerifier -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | success/cancel/offline/expiry each produce one truthful shared-state result | `results/auth/reauth.xcresult` |
| AC-AUTH-02-06 | AUTH-06-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --derived-data /private/tmp/Chapterflow-DD-auth-<SHA> --test ChapterFlowUITests/AuthNativeMatrixTests/testAuthAndReauthMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/auth/native-matrix` | every dimension and real translation preserve copy, actions, focus, announcements, targets, and recovery | `results/auth/native-matrix/manifest.json` plus pinned iPhone/iPad `.xcresult` bundles and catalog/accessibility report |

Every selector requires `matched >= 1`, `failed = 0`, `skipped = 0`, and no disabled/known-issue waiver. `AC-AUTH-02-01` also requires signed-device scenario `DEVICE-AUTH-KEYCHAIN-SIWA-A2B` in WP-DEVICE-01 before device validation is complete.

## Supporting gates

- `swift test --package-path Packages/AuthKit --parallel`
- `swift test --package-path Packages/Persistence --parallel`
- repository-standard unsigned build plus `xcodebuild -showBuildSettings` target mapping; signed
  runtime remains the WP-DEVICE-01 gate
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Missing signing/device/provider authority is blocked, not skipped. Any secret leak, group mismatch, isolation failure, unresolved policy, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
