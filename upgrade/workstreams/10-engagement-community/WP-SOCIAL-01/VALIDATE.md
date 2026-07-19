# Validate WP-SOCIAL-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Repository | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|---|
| AC-SOCIAL-01-01 | SOCIAL-01-INVENTORY-01 | iOS | `swift test --package-path Packages/SocialFeature --filter SocialSurfaceInventoryTests` | D-SURFACE-01 makes every visible action verified/implemented or absent/truthfully unavailable | `results/social/surface-inventory.json` with decision ID and iOS candidate SHA |
| AC-SOCIAL-01-02 | SOCIAL-02-BE-01 | backend | `npx tsx --test app/app/api/book/me/safety/safety.test.ts` | storage/authority timeout/error fails block/report closed with no fake success or private payload | `results/social/backend-safety.tap` with backend candidate SHA |
| AC-SOCIAL-01-02 | SOCIAL-02-IOS-01 | iOS | `swift test --package-path Packages/SocialFeature --filter SafetyActionFailureTests` | iOS retains truthful actionable failed/uncertain state and does not claim protection | `results/social/ios-safety.json` |
| AC-SOCIAL-01-03 | SOCIAL-03-UNIT-01 | iOS | `swift test --package-path Packages/SocialFeature --filter SocialAuthorityTests` | unknown gift/referral/reward grants no entitlement/reward and exposes safe recovery | `results/social/authority.json` |
| AC-SOCIAL-01-04 | SOCIAL-04-IOS-01 | iOS | `swift test --package-path Packages/SocialFeature --filter SocialPrivacyTests` | iOS log and analytics spies contain no PII/private content/report/token/raw ID | `results/social/ios-privacy.json` with iOS candidate SHA |
| AC-SOCIAL-01-04 | SOCIAL-04-BE-01 | backend | `npx tsx --test app/app/api/book/me/safety/privacy.test.ts` | when D-SURFACE-01 selects backend work, backend log spies contain no PII/private content/report/token/raw ID; otherwise inventory records this row not applicable | `results/social/backend-privacy.tap` with backend candidate SHA or inventory-bound not-applicable record |
| AC-SOCIAL-01-05 | SOCIAL-05-UI-01 | iOS | `xcodebuild test -project ChapterFlow.xcodeproj -scheme ChapterFlow -derivedDataPath /private/tmp/Chapterflow-DD-social-<SHA> -destination 'platform=iOS Simulator,id=<PINNED_UDID>' -resultBundlePath results/social/recovery.xcresult -only-testing:ChapterFlowUITests/SocialSafetyTests/testOfflineRateLimitCancelRepeatExpiryAndAccountSwitch -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | destructive state, focus, localization, and server truth survive all recovery cases | `results/social/recovery.xcresult` plus accessibility report |
| AC-SOCIAL-01-06 | SOCIAL-06-UI-01 | iOS | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/SocialNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-social-matrix-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/social/native-matrix` | every required dimension preserves localized content/actions, fail-closed safety truth, focus, semantics, and targets | `results/social/native-matrix/manifest.json` plus pinned iPhone/iPad `.xcresult` bundles and catalog/accessibility report |

Every selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Backend rows run only when D-SURFACE-01 selects additive backend work; otherwise the inventory must prove the production entry point absent and backend PR metadata unused.

## Supporting gates

- full SocialFeature/Networking suites; backend focused tests, typecheck, and full tests if used
- compatibility/merge-order proof and repository-standard unsigned app build
- per-repo candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Unresolved D-SURFACE-01, fail-open moderation, local reward grant, privacy leak, false success, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
