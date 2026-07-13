# ChapterFlow iOS CI Performance and Optimization

Status: WP-CI-01 Stage A1 branch candidate for Stage A2
Baseline cutoff: 2026-07-13 06:52 UTC
Historical baseline revision: `92a5c351a42771f546b3d0e575b3b37a8cbfb588`
Integration base: `82f6674fd180cb787a4b4c5366dfdd938cb76f5b`
Historical legacy workflow blob: `6df048379550bf869cdf4af37710fc6f6afc50ac`
Integration legacy workflow blob: `e3fdd1ef236d78a1f30ad916d2ffef7372a26aa1`

This document records measured legacy behavior, the coverage-preserving CI v2
candidate, its security model, and the evidence required before a later
required-check cutover. The legacy `.github/workflows/pr.yml` remains unchanged
from the integration base and authoritative throughout Stage A1 and Stage A2.

## 1. Goals and guardrails

WP-CI-01 optimizes time from a PR push to a trustworthy green result. It does
not reduce product-test coverage, change production Swift behavior, or perform
release work.

Targets derived from the baseline are:

- typical single-feature PR p50 at or below 30 minutes, a reduction of at least
  40% from the 50:59 legacy p50;
- full-scope PR p50 at or below 35:41, a reduction of at least 30%;
- docs-only `CI / Required` in a few minutes without a macOS runner;
- no omitted owning package or transitive local reverse dependency;
- mandatory full validation for shared, configuration, workflow, app-host, and
  UI-test changes;
- no retry, waiver, `continue-on-error`, or condition that can create a silent
  green;
- no compiled cache unless measured restore and save cost is materially below
  the compilation time it replaces.

## 2. Measured legacy baseline

### 2.1 Sample and method

The primary sample contains 19 completed runs from the historical three-job
workflow/cache topology beginning at `ef39f3dc`:

- 13 succeeded;
- 3 failed;
- 3 were cancelled by a superseding run;
- 8 successful PR runs form the time-to-green percentile population;
- PR #117 runs are excluded because its branch-local workflow is materially
  different from the historical baseline `main` topology;
- no queried run was a rerun (`run_attempt` was 1 throughout).

Wall time is `updated_at - created_at`. Runner time is the sum of job
`completed_at - started_at`. Percentiles use linear interpolation. Job and step
timestamps came from the GitHub Actions API and connected job logs. The raw
run, job, queue, and major-step observations used below are checked in as
`scripts/ci/baseline-runs.json` so the aggregates can be reproduced.

| Run | Event | Result | SHA | Wall | Runner | Category |
|---:|---|---|---|---:|---:|---|
| 29228928000 | PR | cancelled | `841a33b5` | 6:16 | 5:48 | superseded |
| 29226923797 | PR | cancelled | `bb7ca300` | 44:15 | 44:26 | superseded |
| 29225201907 | PR | success | `a8a8dc56` | 49:07 | 49:12 | — |
| 29221391746 | push | failure | `92a5c351` | 29:08 | 29:17 | cache/infrastructure |
| 29219419365 | PR | success | `57cece78` | 52:51 | 53:00 | — |
| 29134271373 | push | success | `03747305` | 43:02 | 43:09 | — |
| 29132580794 | PR | success | `d73db4b1` | 48:37 | 48:43 | — |
| 29127217034 | push | success | `7291e8c3` | 57:49 | 57:51 | — |
| 29124763228 | PR | success | `10af7a96` | 47:15 | 47:21 | — |
| 29091483221 | push | success | `a8e48ad6` | 54:16 | 54:22 | — |
| 29088174532 | PR | success | `ec3210cd` | 62:41 | 62:54 | — |
| 29087440981 | PR | failure | `95b14420` | 10:22 | 10:31 | source compile |
| 29084684724 | push | failure | `87a189b8` | 46:34 | 46:38 | lint/source |
| 29084657111 | push | cancelled | `ca2b11bb` | 0:37 | 0:52 | superseded; lint also failed |
| 29082194607 | push | success | `26346622` | 43:54 | 44:05 | — |
| 29081335103 | PR | success | `ba903559` | 58:58 | 59:09 | — |
| 29080967625 | PR | success | `ea18276a` | 48:46 | 49:04 | — |
| 29077017931 | PR | success | `68a75860` | 56:16 | 56:27 | — |
| 29074913754 | push | success | `ef39f3dc` | 52:42 | 52:31 | cold cache seed |

The sample totals 13:33:26 wall time and 13:35:20 runner time. Cancelled runs
consumed 51:06 of runner time. Cancellation rate is 15.8%; cache-caused failure
rate is 5.3%; observed rerun rate is 0%.

### 2.2 Time to green

The repository currently has no required checks, so “required green” here means
the operational proxy of the entire legacy PR workflow succeeding.

| Population | n | Wall p50 | Wall p90 | Runner p50 | Runner p90 |
|---|---:|---:|---:|---:|---:|
| Successful PR runs | 8 | **50:59** | **60:05** | 51:06 | 60:17 |
| All successful PR/push runs | 13 | 52:42 | 58:44 | 52:31 | 58:53 |

Successful PR job percentiles:

| Job | p50 | p90 |
|---|---:|---:|
| Lint | 0:19 | 0:23 |
| Build & Test | 24:04 | 28:07 |
| XCUITest Flows | 28:31 | 31:54 |

The legacy workflow uploaded no artifacts on either success or failure.

Runner queue delay was normally two to five seconds. Runner allocation is not
the cause of the long path.

### 2.3 Critical path and largest consumers

The legacy critical path is:

```text
app build → all package suites sequentially → allocate fresh UI runner
→ resolve/build the application graph again → execute UI tests
```

Major-step percentiles across the eight green PRs:

| Step | p50 | p90 |
|---|---:|---:|
| Build-job Xcode selection/setup | 0:03 | 0:05 |
| Restore 8.01 GB / 7.46 GiB combined source + `.spm-build` archive | 2:44 | 3:23 |
| First app dependency-graph resolution | 1:59 | 2:39 |
| First simulator app build | 9:29 | 12:06 |
| Sequential 17-package loop | 11:32 | 12:52 |
| UI-job Xcode selection/setup | 0:04 | 0:05 |
| Restore 3.44 GB / 3.20 GiB UI source cache | 1:04 | 1:22 |
| Simulator boot | 1:55 | 2:57 |
| Combined `xcodebuild test` | 25:14 | 28:03 |
| UI dependency resolution inside test | 4:56 | 6:31 |
| UI build/setup before XCTest begins | 16:18 | 18:34 |
| Actual deterministic UI suite | 8:10 | 9:01 |

The five largest disjoint p50 consumers are UI build/setup (16:18), package
tests (11:32), the first app build (9:29), UI execution (8:10), and compiled
source-plus-build archive restore (2:44).

Repeat compilation is directly visible in run `29225201907`: Persistence's
`CachedBook.swift` compiled at 05:07:52 UTC in the build job and again at
05:36:11 on the fresh UI runner. The package graph was also resolved twice.

### 2.4 Package timing evidence

The checked timing artifact `scripts/ci/package-durations.json` uses p50 elapsed
seconds between each package's start and completion markers in the same eight
green PR logs.

| Package | p50 | p90 | Package | p50 | p90 |
|---|---:|---:|---|---:|---:|
| Models | 16.9s | 20.5s | CoreKit | 19.4s | 25.8s |
| Networking | 5.1s | 8.6s | Fixtures | 17.8s | 26.8s |
| DesignSystem | 10.7s | 14.1s | AIFeature | 30.2s | 41.8s |
| AuthKit | **241.1s** | **280.6s** | EngagementFeature | 22.5s | 24.9s |
| LibraryFeature | 19.0s | 25.3s | NotificationsFeature | 7.5s | 10.1s |
| OnboardingFeature | 5.1s | 6.6s | PaywallFeature | 8.7s | 10.8s |
| Persistence | 7.5s | 8.5s | QuizFeature | 18.7s | 21.1s |
| ReaderFeature | 10.8s | 14.7s | SettingsFeature | **206.4s** | **263.9s** |
| SocialFeature | 13.8s | 19.9s | | | |

`AuthKit` and `SettingsFeature` account for about 68% of summed package p50.
`AppFeature` and `SyncEngine` have test targets but were omitted by the
historical legacy loop. Merged WP-DEV-01 added the narrow macOS host guards;
`swift test --package-path Packages/AppFeature` now passes 67 tests in 18 Swift
Testing suites. Neither package has a historical legacy p50, so both use the
existing conservative unmeasured 60-second planner default until a reviewed
duration-artifact update is supported by sufficient recorded samples. No
historical AppFeature p50 is inferred or fabricated.

### 2.5 Cache evidence and failure

All eight green PRs exact-hit both legacy keys. GitHub's log labels the reported
cache units as `MB`; the byte values below are authoritative and are also shown
as decimal GB and binary GiB:

| Cache | Exact legacy key | Size | Restore p50 | First trusted save |
|---|---|---:|---:|---:|
| Sources plus compiled `.spm-build` | `macOS-spm-v2-04508db5ac7850933218111f0cd746b4afb54fef1380d64344de0021b49a1ebb` | 8,010,285,129 B / 8.01 GB / 7.46 GiB | 2:44 | 93.2s |
| UI dependency sources | `macOS-spm-04508db5ac7850933218111f0cd746b4afb54fef1380d64344de0021b49a1ebb` | 3,438,216,704 B / 3.44 GB / 3.20 GiB | 1:04 | 60.5s |

Legacy keys omit architecture, exact Xcode build, Swift version, manifests, and
shard identity. Run `29221391746`, a docs-only main push, restored the exact
3.44 GB / 3.20 GiB source-only UI cache and then failed after 29:08: `gtar`
exited 2 and an AWS SDK checkout reported a corrupt inflate stream. The
combined source-plus-`.spm-build` cache succeeded in that run; it is not the
source of this observed failure. CI v2 restores neither legacy key family
because both omit required invalidation inputs.

### 2.6 Data limitations

- UI build versus execution is inferred from package resolution and XCTest
  suite timestamps because the legacy workflow emitted no structured metrics.
- Cache quota/inventory APIs and admin-only repository settings were
  inaccessible with the invalid local `gh` credential.
- Runner totals are elapsed job time, not rounded billable minutes.
- SyncEngine and AppFeature have no historical legacy duration because the
  legacy 17-root loop omitted both. Their 60-second weights are conservative
  defaults, not measured p50 values.

## 3. Candidate architecture

`.github/workflows/pr-v2.yml` always starts. It has no workflow-level path
filter and uses `contents: read` permissions.

```text
plan (Linux, fail-closed)
├── lint (Linux, pinned SwiftLint)
├── package-tests (macOS, measured matrix, max-parallel 2)
└── app-and-ui (macOS, same runner and DerivedData)
    ├── WP-DEV-01 non-Debug compile-boundary probe (once when app is selected)
    ├── app-only: xcodebuild build
    └── UI: build-for-testing → test-without-building

required (Linux, always, no checkout/network)
```

After `plan`, lint, package tests, and app/UI start independently. UI no longer
waits for package tests. When UI is selected, there is no preceding standalone
app build and no build artifact transfer; one runner and one DerivedData tree
are used for `build-for-testing` and `test-without-building`.

Every job has a timeout and Step Summary. Failure-only artifacts retain planner
JSON, lint output, package logs/metrics, scoped raw xcodebuild logs, and
`.xcresult` for five days. The workflow does not claim these raw diagnostics are
redacted. Success builds are not uploaded.

The App & UI job runs `scripts/verify-wp-dev-01-compile-boundaries.sh` exactly
once after exact toolchain setup whenever app validation is selected. A normal
step failure fails the owning job. The aggregate also checks the raw step
outcome, so a future accidental `continue-on-error` cannot mask the invariant.
The corresponding legacy-workflow step remains unchanged.

The aggregate job accepts only `success` for required work and only `skipped`
for explicitly unrequired work. Missing/malformed plans, matrices that omit or
duplicate packages, unexpected skips, failures, and cancellations fail closed.
PR and merge-group runs use the future context `CI / Required`; main, schedule,
and manual full/benchmark/clean runs use `CI Full / Required`. Manual affected
runs use `CI Advisory / Required`, so neither a manual partial run nor another
event can satisfy a protected PR or full context accidentally.

## 4. Change planner rules

The planner compares both sides of rename/copy records from the real merge-base
diff. Missing history, an invalid merge base, an empty diff, an unknown path, or
malformed output selects full scope.

| Change class | Packages | Lint | App | UI | Reason |
|---|---|---:|---:|---:|---|
| Only Markdown under `docs/` or approved root docs | none | no | no | no | Fast checks still run in `plan` |
| Workflow, local action, or `scripts/ci/**` | all 19 host roots | yes | yes | yes | CI can alter every gate |
| `scripts/verify-wp-dev-01-compile-boundaries.sh` | all 19 host roots | yes | yes | yes | Explicit compile-boundary gate |
| Project, scheme, test plan, Config, app host, UI tests | all 19 host roots | yes | yes | yes | Shared/high-risk surface |
| Models, CoreKit, Networking, Persistence, AppFeature, Fixtures, DesignSystem | all 19 host roots | yes | yes | yes | Foundation/shared closure |
| Any `Package.swift` or `Package.resolved` | all 19 host roots | yes | yes | yes | Build/dependency topology |
| Explicitly allowlisted pure feature logic | owner plus transitive reverse dependents | yes | yes when app-linked | no | Narrow source-backed exception with canary |
| Other UI-bearing feature source, including controls, appearance, sheets, rows, routes, models, auth, navigation, bootstrap, or coordinators | owner plus reverse dependents | yes | yes | yes | Conservative feature-source default |
| Embedded extension-only change | none unless another rule applies | by source | yes | no | App embeds the extension |
| `ci-full`, push main, schedule, merge queue, full/benchmark/clean dispatch | all 19 host roots | yes | yes | yes | Authoritative full mode |
| Unknown/unclassified | all 19 host roots | yes | yes | yes | Fail-safe default |

Docs-only still runs planner self-tests, checked dependency-graph consistency,
`git diff --check`, added-secret patterns, conflict markers, Markdown fence
balance, inline and reference-definition local-link checks, incoming links to
deleted paths, generated Xcode-product checks, and the stable aggregate.

Manual UI `off` is ignored when source risk or full mode requires UI. Full mode
cannot be weakened by package or UI input.

## 5. Package graph and reverse dependencies

`scripts/ci/package-graph.json` is a checked artifact generated from every
`Packages/*/Package.swift` by `swift package dump-package`, including
AppFeature's computed dependency array. Each entry binds the exact manifest
SHA-256. The Linux planner rejects missing/stale manifests cheaply; the macOS
app lane reruns SwiftPM semantic generation and requires exact equality. Unit
tests cover every current package, local dependency shape, and digest.
After an intentional manifest edit, regenerate the artifact with
`python3 scripts/ci/plan.py --print-graph` and replace
`scripts/ci/package-graph.json`; the macOS semantic check is the final proof.

The graph contains 19 package roots with tests, and all 19 are now runnable via
macOS-host `swift test`. The historical legacy loop contains 17 and omitted:

- `AppFeature`; merged WP-DEV-01 now makes its 67 tests host-runnable;
- `SyncEngine`, without a workflow explanation.

CI v2 adds both omitted roots, increasing host-package coverage from 17 to 19.
AppFeature remains covered by mandatory app/UI validation as well as its host
tests. A feature change tests each runnable owner and transitive reverse
dependency. For example:

- `AIFeature` selects `AIFeature`, `LibraryFeature`, and their `AppFeature`
  reverse dependency, plus the app build;
- `SyncEngine` selects `SyncEngine`, `SettingsFeature`, and `AppFeature`, plus
  the app build;
- `CoreKit` reaches all 19 runnable host roots and is a mandatory full trigger.

All app-linked packages request app validation. Fixtures is the only graph root
that is preview/test-only at the AppFeature composition layer; it is already a
mandatory full trigger because shared fixtures affect hermetic tests.

## 6. Package sharding strategy

Normal full runs use two shards with `max-parallel: 2`. The planner applies a
longest-processing-time balance to measured p50 weights while keeping AuthKit
and SettingsFeature together so their large shared Amplify/AWS graph can reuse
one scratch directory.

Current estimated full shards are:

| Shard | Packages | Historical estimate |
|---|---|---:|
| 1 | AuthKit, SettingsFeature | 447.5s |
| 2 | remaining 17 roots, including AppFeature and SyncEngine at 60s defaults | 333.7s |

This intentionally limits duplicate compilation to two scratch directories,
not 19 independent jobs. Affected selections of six or fewer packages use one shard.
`workflow_dispatch` can exercise one through four shards for benchmark mode,
while job concurrency remains capped at two. The checked timing artifact can be
updated only from recorded run evidence.

The initial imbalance is accepted because separating AuthKit and SettingsFeature
would duplicate their expensive dependency graph. Candidate cold and warm data
must prove whether two shards remain the optimum.

## 7. Cache design and security model

### 7.1 Dependency source cache

CI v2 caches only SwiftPM bare source repositories initially:

```text
~/Library/Caches/org.swift.swiftpm/repositories
```

The primary key contains schema, runner OS, CPU architecture, exact Xcode
version/build, exact Swift version, and the combined hash of every
`Package.swift` and `Package.resolved`. Restore prefixes never cross toolchains.

PR and merge-group jobs use `actions/cache/restore` only. Only trusted push,
schedule, and manual runs may save, only after successful app validation, only
on an exact-key miss, and only below the explicit 4 GiB source-cache budget.
Manual `clean` disables even source-cache restore. The nightly path never uses
a compiled cache.

Cold advisory run `29233015194` had zero hits across its three restore attempts;
each miss check took one to two seconds and transferred no archive. The app lane
measured 3,476,852,736 bytes (3.24 GiB, 81.0% of budget) after dependency
resolution. Cache save was correctly skipped for the pull-request event, so no
one-off PR cache was created.

On the same commit, legacy run `29233015113` restored its 8,010,285,129-byte
combined archive in 2:21, then missed the separate source-only key on the fresh
UI runner. CI v2 remained faster in wall time without restoring compiled state,
but its runner-time increase shows that this cold result is a tradeoff, not a
free cache win.

The old `macOS-spm-*` family is not a restore fallback because it produced a
confirmed corruption failure and lacks required invalidation inputs.

### 7.2 Compiled SwiftPM and Xcode outputs

The initial candidate does not save `.spm-build`, DerivedData, simulator data,
or build products. The legacy combined source-plus-compiled archive is 8.01 GB
/ 7.46 GiB, consumes 2:44 p50 to restore, and costs about 93 seconds to save.
The legacy evidence does not separate source bytes from compiled bytes, so it
cannot establish a compiled-only size or transfer cost. This large combined
archive also creates material disk pressure on a 14 GB hosted runner.

Manual shard-count benchmarks provide no-cache one/two/three/four-shard
evidence before any compiled-cache experiment. A future compiled cache needs a
shard-specific key, pruned contents, stale-cache canary, explicit size budget,
and measured net savings. Until then, same-job DerivedData reuse is the safe
Xcode optimization.

### 7.3 Never cached

The workflow never caches `Secrets.xcconfig`, environment secrets, tokens,
Keychains, Cognito/JWT data, StoreKit transactions, simulator user data, signed
artifacts, test sessions, user content, or logs. Placeholder config is created
after checkout and is outside every cache path.

## 8. Benchmark protocol and current results

Stage A1 compares the unchanged legacy workflow and CI v2 on the same candidate
PR revision. Stage A2 expands that comparison to representative development
PRs after the advisory workflow exists on `main`. Required classes are
Markdown-only, low-risk feature logic, UI/AppFeature, foundation,
project/lockfile, and full/manual.

For each class, record cold and warm runs where possible:

- time to first actionable failure;
- aggregate green wall time;
- runner time;
- cache restore/save time and bytes;
- selected and executed packages/tests;
- build duplication;
- artifacts, reruns, and flakes.

Current evidence table:

| Scope | Legacy wall p50 | CI v2 branch evidence | CI v2 Stage A2 evidence | Selection equivalence | Status |
|---|---:|---:|---:|---|---|
| Docs-only | full workflow; observed failure at 29:08 | planner-tested | awaiting advisory-on-main sampling | v2 intentionally removes executable work | No isolated GitHub sample |
| Feature logic | 50:59 overall PR p50 | planner-tested | awaiting advisory-on-main sampling | owner + reverse deps, app if linked | No isolated GitHub sample |
| UI/AppFeature | 50:59 | planner-tested | awaiting advisory-on-main sampling | full 19 host roots + app/UI | AppFeature host test independently proven |
| Foundation | 50:59 | planner-tested | awaiting advisory-on-main sampling | full 19 host roots + app/UI | No isolated GitHub sample |
| Project/lockfile | 50:59 | planner-tested | awaiting advisory-on-main sampling | full 19 host roots + app/UI | No isolated GitHub sample |
| Full/manual | 50:59 | **34:55 and 32:08 historical** | awaiting advisory-on-main sampling | current scope is 19 roots + app/UI | Both historical branch samples covered 18 roots |

Advisory run `29233015194` on `ec8df029` is the first historical cold
full-scope measurement. It passed in 34:55 wall time: 18 host roots and 2,100
package tests, plus 20 UI tests with two existing skips. That is 31.5% below
the legacy PR p50 of 50:59 and 46 seconds inside the 35:41 single-run threshold.
It predates merged WP-DEV-01 and therefore does not contain AppFeature host
tests or the compile-boundary integration. It is not a p50, warm-cache result,
representative-class series, or cutover approval.

The unchanged legacy workflow ran on the exact same commit as run
`29233015113`:

| Same-commit result | Legacy | CI v2 | Delta |
|---|---:|---:|---:|
| Green wall time | 49:01 | **34:55** | **-14:06 (-28.8%)** |
| Allocated runner time | 49:07 | 56:14 | +7:07 (+14.5%) |
| Host suites / package tests | 17 / 2,071 | 18 / 2,100 | +SyncEngine / +29 |
| UI tests | 20, two skipped | 20, two skipped | equivalent |

The same-commit legacy run was faster than the historical p50, so this single
pair is 36 seconds outside a 30% same-run reduction even though the candidate
meets the baseline-derived full-scope threshold. More samples are required.

The measured candidate critical path was graph verification 0:24, dependency
resolution 4:36, simulator boot 4:15, build-for-testing 16:25, and
test-without-building 8:04. Package jobs completed independently in 12:38 and
8:40, so further package sharding would not improve this full path.

### 8.1 Historical pre-integration branch pair

A later exact-head branch pair at `dddef9e5d07b772e481ffbf2e7969dd04d6db856`
also predates merged WP-DEV-01:

| Historical exact-head result | Legacy `29238245501` | CI v2 `29238245385` | Delta |
|---|---:|---:|---:|
| Green wall time | 46:08 | **32:08** | **-14:00 (-30.3%)** |
| Allocated runner time | 44:49 | 53:55 | +9:06 (+20.3%) |
| Host roots / package tests | 17 / 2,071 | 18 / 2,100 | +SyncEngine / +29 |
| UI tests | 20, two skipped | 20, two skipped | equivalent |

The candidate source-cache lookup missed and the PR correctly performed no
save. This is another cold single sample, not a p50 or warm-cache claim.

### 8.2 Final-head integration comparison

The exact post-rebase candidate SHA, workflow run IDs, durations, package/test
counts, compile-boundary result, cache state, and runner-time delta will be
recorded in PR #121's description after both workflows finish. Committing those
post-push measurements into this file would create a different head and make
the cited runs historical immediately. This section therefore fixes the
measurement protocol while the PR description carries the revision-bound
exact-final-head integration record.

## 9. Test-selection equivalence canaries

| Canary diff | Expected CI v2 selection |
|---|---|
| Markdown under `docs/` | plan safety checks and aggregate only |
| AIFeature pure audio logic | AIFeature, LibraryFeature, AppFeature; lint; app; no UI |
| LibraryFeature `BookDetailView` | LibraryFeature, AppFeature; lint; app/UI |
| CoreKit source | all 19 host roots; lint; app/UI |
| AppFeature source | all 19 host roots; lint; app/UI |
| Any Package.resolved | all 19 host roots; lint; app/UI |
| ChapterFlowUITests-only | all 19 host roots; lint; app/UI |
| Workflow/planner/graph | all 19 host roots; lint; app/UI |
| WP-DEV-01 compile-boundary script | all 19 host roots; lint; app/UI |
| `ci-full` label | all 19 host roots; lint; app/UI |
| Unknown path or missing merge base | all 19 host roots; lint; app/UI |

Unit tests also cover rename escape, graph drift, matrix union/uniqueness,
malformed booleans/output, full-mode UI-off rejection, manual package
validation, push, schedule, merge-group, benchmark, and clean modes.

Before Stage B, controlled GitHub canaries must prove deliberate package and UI
failures fail `CI / Required`, a required-job skip fails, a wrong cache key
rebuilds cleanly, and a superseding push cancels the older run. Canary commits
must not remain at the final PR head.

The historical Stage A1 canaries produced the following evidence:

| Canary | Run / revision | Result |
|---|---|---|
| Superseding push cancellation | advisory `29236298032`; legacy `29236298031`; `9f9e495` | Both had active macOS work and completed `cancelled` after push `e114d81`. |
| Package failure plus required app-job skip | advisory `29236400756`; `e114d81` | Both package shards exited through the controlled sentinel; app/UI was deliberately skipped; aggregate failed with `package-tests: expected success, observed 'failure'` and `app-and-ui: expected success, observed 'skipped'`. |
| Wrong-key clean build plus UI failure | advisory `29236609886`; `67c6b2e` | All three restores missed the unique `spm-source-canary-ui-20260713` namespace. Both shards passed all 18 host suites, graph/resolve/simulator passed, and `build-for-testing` completed in 11:24 with `TEST BUILD SUCCEEDED`. The UI sentinel then exited 92 and aggregate failed with `app-and-ui: expected success, observed 'failure'`. |

The combined canaries prove every required failure/skip/cancel behavior without
changing product code. Their short-lived mutations are removed from the final
workflow; the commits remain auditable in branch history.

## 10. Runner-time versus wall-clock tradeoff

Legacy successful PR runner p50 is 51:06 and nearly equals wall time because
the macOS critical path is serialized. CI v2 spends up to three macOS jobs in
parallel: two package shards and one app/UI job. This can increase duplicate
dependency compilation on a cold cache even while wall time falls sharply.

The first cold candidate consumed 56:14 of allocated runner time, 5:08 (10.0%)
above the legacy PR runner p50 while reducing wall time by 16:04. Against the
same-commit legacy run it used 7:07 (14.5%) more runner time while saving 14:06
of wall time. It also ran the newly covered SyncEngine suite. This is the
explicit cost of cold parallel compilation; it is not represented as a runner-
time saving.

The two-shard cap and AuthKit/Settings affinity constrain that cost. No claim of
runner-time improvement is made until representative Stage A2 data exists. A
Stage B cutover requires
the wall-time target plus an explicit recorded runner-time delta; further
sharding is rejected if queue, setup, duplicate compile, or cache transfer
outweighs wall-clock benefit.

## 11. Main, scheduled, and manual confidence lanes

The candidate workflow defines:

- push to `main`: strict lint, all 19 runnable host roots, unsigned app/UI validation,
  planner self-tests, and trusted source-cache warming;
- daily schedule at 05:23 UTC: the same complete validation with no compiled
  cache, graph/planner canaries, and cache size/hit reporting;
- manual `affected`, `full`, `benchmark`, and `clean` modes, optional package
  roots, UI `auto/on/off`, and one-to-four shard experiments.

Manual full/benchmark/clean and scheduled contexts are named
`CI Full / Required`, not the future PR-required context. Manual affected mode
uses `CI Advisory / Required` and therefore cannot substitute for a protected
full or release gate.

## 12. GitHub repository feature review

Read-only GitHub REST evidence on 2026-07-13 shows:

- `main.protected = false`;
- required status enforcement is off and required contexts are empty;
- repository rulesets are `[]`;
- no merge queue is configured;
- default workflow permissions are read-only and workflows cannot approve pull
  requests;
- fork pull requests require approval for first-time contributors;
- automatic branch deletion and auto-merge are disabled, while merge commits,
  squash merges, and rebases are enabled;
- no self-hosted runners are registered.

Therefore the legacy comment claiming two required checks is stale: no check is
actually required today. Stage B should prefer one `CI / Required` context in a
reviewed ruleset or branch-protection rule. If merge queue is enabled,
`merge_group` is already present in CI v2.

Account-level merge-queue eligibility and larger GitHub-hosted runner
availability/billing remain unverified; repository REST state cannot prove
those account capabilities. No runner purchase or infrastructure probe was
attempted.

Recommendations requiring later owner approval:

1. After representative Stage A2 greens, configure one exact `CI / Required`
   context and remove the dynamic legacy contexts only after an overlap period.
2. Keep default workflow permissions read-only and require explicit job-level
   grants for future mutations.
3. Enable Dependabot updates for GitHub Actions while retaining immutable SHA
   pins and version comments.
4. Keep fork PRs on ephemeral GitHub-hosted runners with restore-only caches.
5. Do not attach arbitrary PR code to a persistent self-hosted Mac.
6. Evaluate a larger macOS runner only with billed cold/warm benchmark evidence;
   no purchase or infrastructure change is authorized by WP-CI-01.

## 13. Required-check migration plan

### Stage A1 — branch candidate

1. CI v2 runs on PR #121.
2. Legacy CI remains unchanged and authoritative.
3. Candidate behavior, selection equivalence, and failure canaries are
   evaluated.
4. No repository-setting change occurs.

### Stage A2 — advisory workflow on main

1. PR #121 may merge after independent review.
2. Legacy CI remains unchanged and authoritative.
3. CI v2 runs beside legacy on real development PRs.
4. Trusted main, scheduled, and authorized manual runs may seed the source
   cache.
5. No required-check or branch-protection change occurs.

### Stage B — authoritative cutover

1. A separate owner-authorized PR and repository-setting action are required.
2. `CI / Required` becomes the protected PR context.
3. Legacy PR execution is retired or converted to a manual/full fallback only
   after equivalence is accepted.
4. Full validation remains on main, schedule, clean dispatch, and milestone
   gates.
5. Merge queue is added only if account support and policy are confirmed.

## 14. Rollback

During Stage A1, rollback is abandoning the branch candidate; legacy CI is
unchanged. During Stage A2, rollback is deletion or disablement of advisory
`pr-v2.yml`; legacy CI never stopped. After a separately authorized Stage B
cutover, rollback is one reviewed commit that restores the last known-good
authoritative workflow, followed by restoration of the former exact
required-check settings. Cache schema keys are additive; no cache deletion is
needed for correctness. Never weaken or waive tests during rollback.

## 15. Known limitations and open evidence

- Two cold pre-WP-DEV full-scope candidate samples are recorded. Neither is a
  p50, and representative docs/feature/UI/foundation/project classes remain
  planner evidence rather than live Stage A2 timing evidence.
- New default-branch cache keys cannot be seeded for sibling PRs until the
  candidate exists on `main`. Manual branch dispatch can measure cold/warm
  transfer but not prove cross-PR default-branch reuse. GitHub also requires a
  manually dispatched workflow to exist on the default branch; during Stage
  A1, full/manual dry runs therefore require an equivalent temporary
  push-triggered canary or await the approved Stage A2 advisory merge.
- AppFeature and SyncEngine expand runnable host-package coverage from 17 to
  19. Both use conservative 60-second weights until a reviewed duration-artifact
  update is supported by sufficient recorded samples. AppFeature changes
  continue to require app/UI validation, and no legacy test was removed.
- Current UI tests contain two conditional skips and the named read/quiz/unlock
  flow does not yet exercise those product actions. WP-CI-01 preserves the
  current target and does not edit PR #119-owned test/bootstrap surfaces.
- Current shared scheme has no active StoreKit configuration on `main` despite
  historical workflow prose. Release/StoreKit work remains frozen and out of
  scope.
- No physical-device behavior is exercised; CI changes do not alter app runtime
  behavior.

## 16. Official GitHub references

- [Dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
- [Workflow concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
- [Matrix jobs and max-parallel](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations)
- [Reusable workflows versus composite actions](https://docs.github.com/en/actions/concepts/workflows-and-actions/reusing-workflow-configurations)
- [Workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts)
- [Required-check skip behavior](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)
- [Merge queue and merge_group](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)
- [Least-privilege GITHUB_TOKEN](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)
- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Self-hosted runner security guidance](https://docs.github.com/en/actions/reference/security/secure-use)
- [Larger runner availability and billing](https://docs.github.com/en/actions/concepts/runners/larger-runners)
