# Validate WP-PAYWALL-01

Record every command/scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. Required
selectors pass only with `matched >= 1`, `failed = 0`, `skipped = 0`; no waiver.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-PAYWALL-01-01 | PAYWALL-01-UNIT-01 | `swift test --package-path Packages/PaywallFeature --filter PaywallTruthfulStateTests` | pending/cancel/unavailable/offline/restore/verifier/already-Pro states remain distinct | `results/paywall/states.json` with candidate SHA and nonzero match/pass/skip counts |
| AC-PAYWALL-01-02 | PAYWALL-02-AUTHORITY-01 | `swift test --package-path Packages/PaywallFeature --filter StoreKitAuthorityTests` | StoreKit-only success never grants Pro/unlock and finish follows verified reconciliation | `results/paywall/authority.json` |
| AC-PAYWALL-01-03 | PAYWALL-03-LIFETIME-01 | `swift test --package-path Packages/PaywallFeature --filter PaywallOperationLifetimeTests` | repeated/cancelled/stale operations single-flight and expose no receipt/identifier | `results/paywall/lifetime.json` |
| AC-PAYWALL-01-04 | PAYWALL-04-ACCOUNT-01 | `swift test --package-path Packages/PaywallFeature --filter PaywallAccountIsolationTests` | late A entitlement cannot publish or grant for B | `results/paywall/account-isolation.json` |
| AC-PAYWALL-01-05 | PAYWALL-05-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --derived-data /private/tmp/Chapterflow-DD-paywall-<SHA> --test ChapterFlowUITests/PaywallNativeMatrixTests/testCompleteMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/paywall/native-matrix` | every dimension and real translation preserves consequences/actions/focus/announcements/targets | `results/paywall/native-matrix/manifest.json` plus iPhone/iPad `.xcresult` bundles and catalog/accessibility report |
| AC-PAYWALL-01-06 | PAYWALL-06-RECONCILE-01 | `swift test --package-path Packages/PaywallFeature --filter PaywallBackgroundRelaunchReconciliationTests` | background/foreground and relaunch recover one stable operation, reject stale callbacks, retain truthful pending state, and never grant Pro or finish outside verified server reconciliation | `results/paywall/background-relaunch-reconciliation.json` with lifecycle steps, operation identity, authority/finish assertions, and match/pass/skip counts |

## Supporting gates

- `swift test --package-path Packages/PaywallFeature --parallel`
- StoreKit Test configuration audit, dependent app tests, repository-standard unsigned build
- intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and
  post-merge CI

Any local authority grant, false state, cross-account exposure, private evidence, missing native/localization
dimension, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
