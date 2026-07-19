# Validate WP-ENGAGE-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-ENGAGE-01-01 | ENGAGE-01-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/EngagementNativeMatrixTests/testDashboardGoalAndChartMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-engage-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/engage/native-matrix` | every required dimension is represented; hierarchy, localized copy, semantics, and actions remain usable | `results/engage/native-matrix/manifest.json` plus pinned iPhone and iPad `.xcresult` bundles with candidate SHA and scenario/accessibility report |
| AC-ENGAGE-01-02 | ENGAGE-02-UNIT-01 | `swift test --package-path Packages/EngagementFeature --filter DashboardPartialFailureTests` | valid sections survive independent failure and retry/status remains scoped | `results/engage/partial-failure.json` with match/pass/skip counts |
| AC-ENGAGE-01-03 | ENGAGE-03-UNIT-01 | `swift test --package-path Packages/EngagementFeature --filter ChartAccessibilityTests` | localized semantic summary and navigable values preserve chart meaning | `results/engage/chart-accessibility.json` |
| AC-ENGAGE-01-04 | ENGAGE-04-UNIT-01 | `swift test --package-path Packages/EngagementFeature --filter EngagementRouteTests` | each visible journey/event action emits one exact typed destination or truthful unavailable state | `results/engage/routes.json` |
| AC-ENGAGE-01-04 | ENGAGE-04-APP-01 | `swift test --package-path Packages/AppFeature --filter JourneyEventRoutingTests` | AppModel consumes each typed destination exactly once and has no generic-tab fallback | `results/engage/app-routing.json` |
| AC-ENGAGE-01-05 | ENGAGE-05-UNIT-01 | `swift test --package-path Packages/EngagementFeature --filter EngagementAuthorityTests` | unknown/partial reward, tier, badge, goal, or progress grants nothing and is not color-only | `results/engage/authority.json` |
| AC-ENGAGE-01-06 | ENGAGE-06-UNIT-01 | `swift test --package-path Packages/EngagementFeature --filter EngagementAccountIsolationTests` | account A dashboard/reward/route/snapshot state is absent after sign-out and cannot appear for account B | `results/engage/account-isolation.json` |
| AC-ENGAGE-01-07 | ENGAGE-07-UNIT-01 | `swift test --package-path Packages/EngagementFeature --filter SharedSnapshotPublisherTests` | publication exactly matches WP-EXT-01's versioned owner-bound schema and unknown owner publishes nothing | `results/engage/snapshot-publisher.json` |
| AC-ENGAGE-01-08 | ENGAGE-08-STATES-01 | `swift test --package-path Packages/EngagementFeature --filter EngagementAdverseStateTransitionTests` | loading, cached/partial, empty, error/retry, offline, cancellation/repeated refresh, auth expiry, background/foreground, relaunch, and recovery keep valid sections, reject stale commits, and never invent authority | `results/engage/adverse-state-transitions.json` with named state/transition coverage and match/pass/skip counts |

Every selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Build/screenshot/broad-suite-only evidence cannot satisfy an AC.

## Supporting gates

- `swift test --package-path Packages/EngagementFeature --parallel`
- repository-standard unsigned Debug simulator build
- candidate-head intended-path/secret scan, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any invented authority, inaccessible chart, route fallback, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
