# Validate WP-ACCOUNT-02

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Repository | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|---|
| AC-ACCOUNT-02-01 | ACCOUNT-01-IOS-01 | iOS | `swift test --package-path Packages/Networking --filter AccountContractTests` | client encodes the canonical confirmation/recent-auth body and exact error envelope | `results/account/ios-contract.json` with iOS candidate SHA and match/pass/skip counts |
| AC-ACCOUNT-02-01 | ACCOUNT-01-BE-01 | backend | `npx tsx --test app/app/api/book/me/account/delete/route.test.ts` | valid literal confirmation is accepted; missing/wrong/expired confirmation is rejected | `results/account/backend-delete.tap` with backend candidate SHA |
| AC-ACCOUNT-02-02 | ACCOUNT-02-BE-01 | backend | `npx tsx --test app/app/api/book/_lib/account-guard.test.ts` | timeout/error/unknown account status fails closed with safe request ID and no payload | `results/account/account-guard.tap` |
| AC-ACCOUNT-02-03 | ACCOUNT-03-IOS-01 | iOS | `swift test --package-path Packages/SettingsFeature --filter AccountDeletionFailureRecoveryTests` | pre-authority failure preserves private state, shows no success, and retains retry/reauth | `results/account/failure-recovery.json` |
| AC-ACCOUNT-02-04 | ACCOUNT-04-IOS-01 | iOS | `swift test --package-path Packages/SettingsFeature --filter AccountDeletionSuccessTeardownTests` | authoritative success quiesces, purges/quarantines, and publishes signed-out once | `results/account/success-teardown.json` |
| AC-ACCOUNT-02-05 | ACCOUNT-05-PROVENANCE-01 | coordinated | `swift test --package-path Packages/SettingsFeature --filter BackendProvenanceTests` | source and deployed revisions/evidence types remain separate and unknown deployment grants no runtime claim | `results/account/backend-provenance.json` with both repo heads |
| AC-ACCOUNT-02-06 | ACCOUNT-06-UI-01 | iOS | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --derived-data /private/tmp/Chapterflow-DD-account-<SHA> --test ChapterFlowUITests/AccountSettingsNativeMatrixTests/testDeletionRecoveryAndAppLockMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/account/native-matrix` | every required dimension and real translation preserve consequences/actions/focus/announcements/targets/status | `results/account/native-matrix/manifest.json` plus pinned iPhone/iPad `.xcresult` bundles and catalog/accessibility report |
| AC-ACCOUNT-02-07 | ACCOUNT-07-POLICY-01 | iOS | `swift test --package-path Packages/SettingsFeature --filter AppLockPolicyTests` | approved enforcement/recovery is complete or the production control is absent/truthfully unavailable | `results/account/app-lock-policy.json` with D-LOCK-01 disposition |
| AC-ACCOUNT-02-08 | ACCOUNT-08-SWITCH-01 | iOS | `swift test --package-path Packages/SettingsFeature --filter AccountSettingsSwitchIsolationTests` | A deletion/recovery, App Lock, cached-status, and in-flight state is cancelled/cleared and cannot render, authorize, delete, lock, or mutate for B | `results/account/account-switch-isolation.json` with A/sign-out/B steps, owner keys, cancellation proof, and match/pass/skip counts |

Every selector must match at least one test with zero failures/skips/waivers. Backend commands run in the declared backend worktree at its exact candidate head; iOS commands run in the iOS worktree. Both heads are recorded.

## Supporting gates

- full Networking and SettingsFeature suites; backend `npm run typecheck` and `npm test`
- compatibility/merge-order proof, repository-standard unsigned app build
- per-repo intended-path/secret scan, `git diff --check`, independent review, exact-head required CI, merge ancestry, and affected post-merge CI

Unknown deployment blocks deployed behavior, not source work. Any fail-open path, false success, candidate mismatch, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
