# Validate WP-LEARN-01

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required selector passes only when it reports `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance evidence

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-LEARN-01-01 | LEARN-01-QUIZ-01 | `swift test --package-path Packages/QuizFeature --filter QuizMutationIdentityTests` | repeated quiz taps yield one stable mutation and one authoritative request | `results/learn/quiz-mutation-identity.json` with candidate SHA and selector counts |
| AC-LEARN-01-01 | LEARN-01-REVIEW-01 | `swift test --package-path Packages/EngagementFeature --filter ReviewMutationIdentityTests` | repeated review taps yield one stable mutation and one authoritative request | `results/learn/review-mutation-identity.json` with candidate SHA and selector counts |
| AC-LEARN-01-02 | LEARN-02-UNIT-01 | `swift test --package-path Packages/QuizFeature --filter QuizOfflinePendingTests` | exact answer payload survives relaunch and UI remains pending, never synthetic pass/fail | `results/learn/offline-pending.json` |
| AC-LEARN-01-03 | LEARN-03-QUIZ-01 | `swift test --package-path Packages/QuizFeature --filter QuizStaleAttemptTests` | stale quiz state refreshes once, never resubmits, and restores input only for matching identity | `results/learn/quiz-stale-reconciliation.json` |
| AC-LEARN-01-03 | LEARN-03-REVIEW-01 | `swift test --package-path Packages/EngagementFeature --filter ReviewStaleScheduleTests` | stale review state refreshes once and never applies another account's schedule | `results/learn/review-stale-reconciliation.json` |
| AC-LEARN-01-04 | LEARN-04-UNIT-01 | `swift test --package-path Packages/SyncEngine --filter ReviewMutationMigrationTests` | supported duplicate/legacy work migrates exactly once; uncertain/unknown work is retained or quarantined | `results/learn/migration.json` |
| AC-LEARN-01-05 | LEARN-05-UNIT-01 | `swift test --package-path Packages/QuizFeature --filter QuizResultAuthorityTests` | only server result controls correctness, schedule, unlock, reward, and progress | `results/learn/server-authority.json` |
| AC-LEARN-01-06 | LEARN-06-UI-01 | `python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj --scheme ChapterFlow --test ChapterFlowUITests/QuizReviewNativeMatrixTests/testAdaptiveLocalizedAccessibleMatrix --iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> --scenarios scripts/visual/native-matrix.json --derived-data /private/tmp/Chapterflow-DD-learn-<SHA> --require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer --output results/learn/native-matrix` | every required dimension preserves localized content, answers, feedback, focus, and targets | `results/learn/native-matrix/manifest.json` plus pinned iPhone and iPad `.xcresult` bundles plus scenario/accessibility report |
| AC-LEARN-01-07 | LEARN-07-QUIZ-ACCOUNT-01 | `swift test --package-path Packages/QuizFeature --filter QuizAccountSwitchIsolationTests` | account A in-progress answers, pending grading, cached result, and stale tasks are absent for B; only owner-matching durable work can resume | `results/learn/quiz-account-switch.json` with A/sign-out/B steps, task-cancellation proof, owner keys, and match/pass/skip counts |

Every selector requires nonzero matches, zero failures/skips, and no disabled/known-issue waiver. Broad suites/builds are supporting only.

## Supporting gates

- full QuizFeature, EngagementFeature, and SyncEngine suites plus affected Persistence tests
- repository-standard unsigned Debug simulator build
- candidate-head intended-path/secret scan, migration compatibility proof, `git diff --check`, independent review, required CI, merge ancestry, and post-merge CI

Any local grade/unlock, duplicate mutation, uncertain-work loss, candidate drift, failed/skipped selector, or unresolved P0/P1/P2 blocks merge.
