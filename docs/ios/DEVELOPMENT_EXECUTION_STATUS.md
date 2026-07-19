# ChapterFlow iOS Development Execution Status

**Work package:** `WP-DEV-00` - Trustworthy Development Baseline
**Baseline completed:** 2026-07-12, America/Halifax
**Control-plane publication:** 2026-07-13
**Status:** Baseline complete; production implementation not started

## Outcome

WP-DEV-00 established a reproducible current-main development baseline and a safe extraction plan for reusable application-correctness work in deferred PR #117.

Current iOS main passed the deterministic repository gates after generated-build storage was cleared and the exact commands were rerun:

- strict SwiftLint: **PASS**, 0 violations in 726 files;
- Debug iOS Simulator build: **PASS** on an exact retry after one non-reproduced cold link-stage failure;
- all 17 current-main CI package targets: **PASS**;
- current-main XCUITest command: **PASS**, 20 tests executed, 2 explicitly skipped real-API smoke tests, 0 failures;
- normal simulator launch: **PASS** to the unauthenticated ChapterFlow choice screen without stub or auth-bypass flags.

The baseline did not change production code or the test harness. It does not claim live authentication, deployed-backend behavior, physical-device signing, account switching, offline lifecycle, or full reader/quiz/annotation runtime behavior.

## Exact revisions

| Scope | Revision/state | Evidence |
|---|---|---|
| iOS GitHub `main` | `03747305819eccc8bb3c738a21e79d78a82d587d` | Connected GitHub read and clean worktree HEAD |
| Backend GitHub `main` at baseline | `968ff67ecafbed7e8e1d4c7b77badf507cfc5aee` | Connected GitHub read |
| Historical backend audit baseline | `94428c5f5c575773c7df9804c172a9508e427c0f` | Inherited audit/playbook evidence only; no longer backend `main` |
| PR #117 base | `03747305819eccc8bb3c738a21e79d78a82d587d` | GitHub PR and merge-base inspection |
| PR #117 head | `7bb9b5a88494027832cfe1553cc3c6c464702ab6` | GitHub PR and frozen worktree inspection |
| PR #117 state | open draft, unmerged; 19 commits; 125 files; 15,706 additions; 1,492 deletions | Read-only GitHub inspection |

iOS `main` remained at the audited baseline throughout WP-DEV-00. Backend `main` advanced after the audit to `968ff67e...`. Every backend-dependent package must revalidate historical paths, line references, serializers, request/response contracts, and deployment assumptions before implementation. Backend source `main` is not evidence of the deployed revision.

## Preservation and isolation

The existing primary checkout was dirty before WP-DEV-00 with unrelated localization, project-user-data, project-file, repo-local tooling, and documentation work. It was not reset, cleaned, stashed, staged, or edited.

The deferred release worktree was clean on `codex/wp-rel-01` at `7bb9b5a...` when inspected. It was not used as the development base and was not changed.

WP-DEV-00 used an isolated worktree created directly from the verified iOS-main commit. The later publication of these documents also uses a separate documentation-only worktree from `origin/main`.

## Toolchain and targets

| Item | Baseline value |
|---|---|
| Xcode | 26.6, build `17F113` |
| Swift | 6.3.3 |
| SwiftLint | 0.65.0 |
| Simulator | iPhone 17 Pro, iOS 26.5, selected by the current CI algorithm |
| Physical device discovery | iPhone 15 Pro Max, iOS 26.5, paired, Developer Mode enabled; identifiers intentionally omitted |

For compile-only parity, the clean baseline copied the committed `Secrets.example.xcconfig` to ignored `Secrets.xcconfig`, exactly as current CI did. It contained placeholders, not real credentials or an authorized deployment configuration.

## Current-CI validation results

### Strict lint - PASS

```sh
swiftlint lint --strict --reporter github-actions-logging
```

Result: exit 0, 0 violations and 0 serious violations in 726 files. A sandboxed attempt emitted a non-fatal cache-plist permission warning; lint itself passed.

### Debug simulator build - PASS with one transient precursor

```sh
set -o pipefail
xcodebuild build \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

The first escalated cold attempt stopped at the `CreateUniversalBinary`/`Ld` stage; its precise diagnostic was lost to output truncation. The exact command was rerun without source changes and ended `** BUILD SUCCEEDED **`. This remains unresolved transient infrastructure evidence, not a production fix.

### All local package tests - PASS

Current-main CI package list:

```text
Models CoreKit Networking Fixtures DesignSystem AIFeature AuthKit
EngagementFeature LibraryFeature NotificationsFeature OnboardingFeature
PaywallFeature Persistence QuizFeature ReaderFeature SettingsFeature SocialFeature
```

Command shape used for every package, with the worktree substituted for `GITHUB_WORKSPACE`:

```sh
swift test \
  --package-path "Packages/$pkg" \
  --scratch-path "$GITHUB_WORKSPACE/.spm-build" \
  --parallel
```

The first full loop passed Models, then local disk exhaustion caused the remaining invocations to report `No space left on device`. Only generated SwiftPM scratch and baseline DerivedData were removed. The exact full loop was rerun from the beginning and all 17 packages passed. Existing warnings were observed but not suppressed or changed.

### Simulator selection - PASS

The current CI algorithm selected the first available iPhone on the newest installed runtime, booted it, and waited for boot completion. Result: iPhone 17 Pro on iOS 26.5. The local simulator identifier is intentionally not published.

### XCUITest flows - PASS with provenance limitation

Current main did not define a separate non-StoreKit selector. Its only CI UI command ran the full `ChapterFlowUITests` target, including the local StoreKit-configuration `PurchaseFlowTests`. WP-DEV-00 ran that exact command rather than weakening the harness:

```sh
set -o pipefail
xcodebuild test \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination "platform=iOS Simulator,id=<BOOTED_SIMULATOR>" \
  -only-testing:ChapterFlowUITests \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

Results:

- `PurchaseFlowTests`: 6 passed using the local test configuration;
- `ReadQuizUnlockFlowTests`: 6 passed using deterministic fixtures/stubs;
- `SignInFlowTests`: 6 passed using explicit test auth modes;
- `SmokeLaneTests`: 2 skipped because `CF_REAL_API=1` was not set;
- total: 20 executed, 2 skipped, 0 failures;
- command exit: 0 and `** TEST SUCCEEDED **`.

No StoreKit Sandbox account, real purchase, purchase-history inspection, attestation, or release evidence was used. After assertions passed, Xcode could not complete its result-summary artifact because local disk space was exhausted. The test command succeeded, but the result bundle is incomplete evidence.

## Runtime results

### Simulator

The built app was launched normally without XCUITest stub or auth-bypass flags. The first immediate capture showed a brief white transition frame; a subsequent capture showed the ChapterFlow unauthenticated screen with Continue with Apple, Create an account, Log in, and Browse without account.

This proves normal launch reaches the auth choice with placeholder configuration. It does not prove live sign-in or deployed-backend behavior.

### Physical iPhone

A compatible iPhone was available, paired, and in Developer Mode. The project reported automatic signing and bundle ID `com.chapterflow.ios`, but no development team. Physical build/install was therefore **BLOCKED**. No provisioning update, private team identifier, Apple-account selection, or real credentials were requested or inferred.

## Requested behavior register

`PASS` is limited to the named evidence and is not a production-service claim.

| Behavior | Status | Observed evidence |
|---|---|---|
| Launch/bootstrap | PASS | Normal simulator launch reached the unauthenticated choice screen after a brief transition. Stubbed shell launch also passed. |
| Authentication | PASS / BLOCKED | Auth landing, login fields, empty-form disabled state, and test bypass passed. Real Cognito/SIWA was blocked by placeholder configuration and no authorized account. |
| Home | PASS / NOT RUN live | Stubbed Home shell/data checks passed. Live account/backend behavior was not run. |
| Library | PASS / NOT RUN live | Stubbed Library showed a book and no generic error. Live catalog behavior was not run. |
| Search | NOT RUN | Current CI flow has no Search action/assertion. |
| Book Detail | PASS / NOT RUN live | Stubbed book card opened a detail destination. Live detail was not run. |
| Book covers | NOT RUN | The UI test establishes a book card, not remote artwork loading, cache, or fallback behavior. |
| Chapter opening | NOT RUN | Current UI flow stops at Book Detail. |
| Reader navigation | NOT RUN | Reader package tests passed, but no current-main runtime flow navigates the reader. |
| Quiz | NOT RUN | Despite the suite name, the current UI test does not open or submit a quiz. |
| Notes/highlights/bookmarks | NOT RUN | Relevant package logic tests passed; no runtime task was executed. |
| Offline launch | NOT RUN | Current CI has no deterministic offline relaunch assertion. |
| Background/foreground | NOT RUN | Current UI lane has no lifecycle runtime task. |
| Sign-out and second account | NOT RUN | No authorized accounts or dedicated hermetic account-switch UI flow were available. |

## Failure and limitation register

| ID | Area | Observed | Disposition |
|---|---|---|---|
| `DEV00-F01` | Build storage | Shared SwiftPM scratch grew to 8.1 GB and exhausted local free space. | Generated scratch/DerivedData only were removed; exact full rerun passed. Review workspace/cache budgets in later QA work. |
| `DEV00-F02` | Debug build | First cold build ended at link stage; detailed diagnostic was not retained. | Exact no-source-change retry passed. Retain as unresolved transient. |
| `DEV00-F03` | Xcode results | Result-summary construction failed for lack of disk after all UI suites passed. | Assertions and command passed; result artifact remains incomplete. |
| `DEV00-F04` | Runtime coverage | Search, chapter opening, reader navigation, quiz submission, annotations, offline relaunch, lifecycle transitions, sign-out, and account switching lack current-main runtime coverage. | Add focused development integration/UI lanes without weakening existing gates. |
| `DEV00-F05` | Physical device | Suitable device available, but no development team and only placeholder configuration. | Blocked pending authorized development signing/configuration; release proof remains deferred. |

No application-correctness failure was observed in the hermetic flows that actually ran. Unexecuted behaviors remain unknown, not presumed green.

## PR #117 extraction summary

The complete commit/file classification and dependency cautions are in `PR117_EXTRACTION_MATRIX.md`.

| Classification | Files |
|---|---:|
| development configuration/bootstrap | 18 |
| StoreKit/entitlement runtime correctness | 35 |
| hermetic test infrastructure | 58 |
| release-only/deferred | 9 |
| unrelated and requiring a separate PR | 4 |
| reject/drop | 1 complete file, plus waiver hunks in 3 mixed files |
| **Total** | **125** |

The 19 commits are not safe cherry-pick units. The initial 120-file mixed commit must be rejected as an atomic commit while approved logic is reconstructed by file and hunk. The final waiver commit and all waiver/attestation hunks are rejected. The AudioPlayer capture fix is unrelated and requires its own PR.

## Revised development-first order

1. `WP-DEV-00` baseline and extraction plan.
2. `WP-DEV-01 - Deterministic Development Bootstrap`, the first implementation PR.
3. `WP-CONTRACT-01`, `WP-BOOT-01`, development `WP-OBS-01`, hermetic/visual `WP-QA-01`.
4. `WP-NET-01`, `WP-AUTH-01`, `WP-ARCH-01`, `WP-ID-01`, `WP-NAV-01`, then non-release `WP-ENT-01`.
5. Account/durable-data packages, followed by product verticals and product hardening.
6. Final release phase only after separate authorization: `WP-REL-01 -> WP-REL-02 -> WP-REL-03`, then signed-service, Sandbox, TestFlight, App Store, deployment, metadata, and evidence work.

## First implementation PR

**`WP-DEV-01 - Deterministic Development Bootstrap`** should logically reconstruct only the development-safe PR #117 slice:

- API/Cognito/environment configuration parsing and placeholder detection;
- privacy-safe development diagnostics;
- fail-closed validation before service construction;
- explicit invalid-development-configuration routing;
- focused CoreKit/AppFeature tests;
- existing lint, package, Debug build, and UI gates.

Exclude Release/Staging deployment policy, signing identities, release manifests, App Store identity, production StoreKit requirements, Sentry production requirements, TestFlight detection, release snapshots, waiver logic, App Store/TestFlight/Sandbox work, and unrelated Audio/Social changes. Reconstruct approved hunks on a clean branch from latest main; do not cherry-pick the mixed initial commit.

## Blockers and uncertainties

- Live Cognito/SIWA, authenticated backend, account switching, and production-service behavior remain unverified because no authorized credentials/configuration were supplied.
- Backend source `main` was verified; the deployed backend revision was not.
- Physical installation remains blocked without authorized development signing.
- The complete XCUITest result summary was not written after local disk exhaustion.
- The first cold Debug link-stage failure was not reproducible and its complete diagnostic was not retained.
- PR #117 identifiers, pricing, Apple identity, and release assertions are frozen reference material, not newly authorized product decisions.

## Prohibited-action confirmation

WP-DEV-00 performed no App Store Connect metadata action, TestFlight upload, StoreKit Sandbox purchase or attestation, release evidence creation, production deployment, release labeling, PR #117 merge/close/relabel/comment/push, branch push, or other release action. PR #117 and `codex/wp-rel-01` remain deferred and frozen.

---

## WP-DEV-01 - Deterministic Development Bootstrap

**Last remediation update:** 2026-07-13, America/Halifax

**Branch:** `codex/wp-dev-01-bootstrap`

**Status:** Independent verification **FAIL** recorded at `63cdbb06dd2370a8468729231b08228c7a044ba6` with four P2 findings and no P0/P1 findings. The second remediation is locally validated at `ee792b1401563b6593f7eb31bab4de4c6abd8ed5`; draft PR #119 is unmerged and awaiting independent re-verification.

### Outcome and revisions

WP-DEV-01 now rejects missing, empty, unexpanded, example, placeholder, malformed, insecure, or internally inconsistent API/Cognito configuration before any live application service graph is constructed. Valid configuration is converted into a typed capability and constructs the graph once in `ChapterFlowApp.init()`, outside SwiftUI body evaluation.

| Scope | Revision/state |
|---|---|
| Authoritative starting revision | `92a5c351a42771f546b3d0e575b3b37a8cbfb588` |
| Initial tested implementation revision | `53603a2532e8e9ec8b28536009da295b9a1fc522` |
| Remediation starting head | `a8a8dc563289d274ef58cbdbbaa30898693a0376` |
| First remediation tested implementation revision | `8aca1253a3d0ac07f33ec3226d79f3b33cf0dbf8` |
| First remediation/evidence head presented to verifier | `63cdbb06dd2370a8468729231b08228c7a044ba6` |
| Independent verification at `63cdbb...` | **FAIL** - four P2 findings, no P0/P1 findings |
| Second remediation implementation revision | `ee792b1401563b6593f7eb31bab4de4c6abd8ed5` |
| Second remediation evidence revision | Documentation-only successor to `ee792b...`; the final draft PR head is authoritative |
| PR #119 state | Open draft, unmerged, awaiting independent re-verification |
| Branch base and merge-base with `origin/main` | `92a5c351a42771f546b3d0e575b3b37a8cbfb588` |
| Frozen PR #117 reference | `codex/wp-rel-01` at `7bb9b5a88494027832cfe1553cc3c6c464702ab6`, inspected read-only |

The dirty primary `Pro` checkout was not used, reset, stashed, staged, or edited. Work ran in `/private/tmp/Chapterflow-IOS-wp-dev-01-bootstrap`, created directly from the verified starting revision. No backend source or contract changed.

### Independent-verifier findings and second remediation

The independent verifier evaluated `63cdbb06dd2370a8468729231b08228c7a044ba6` and returned **FAIL** for exactly four P2 findings. The table records the red evidence, the second remediation, and the regression proof; it does not convert that verdict into a pass.

| P2 finding at `63cdbb...` | Red evidence | Second remediation | Regression evidence |
|---|---|---|---|
| Bracketed IPv6 loopback was rejected | Foundation preserved `[::1]` as the parsed host, while validation accepted only `::1`, producing `api_base_url:malformed` | Normalize only the exact parsed spelling `[::1]` to `::1` for loopback comparison | Twelve parameterized URL cases cover HTTP/HTTPS bracketed loopback, nonloopback IPv6, a malformed bracket, user info, query, and fragment |
| Support-code privacy was conventional rather than structural | An external caller could inject an arbitrary `supportCode` string into a diagnostic record and reflection retained it | Remove the initializer input and stored property; expose only computed fixed code `CF-DEV-CFG-001` | Reflection checks prove only coarse fields are stored; valid and invalid records return the literal fixed code; a non-Debug external consumer cannot compile a caller-controlled code |
| Hermetic overlay API existed in non-Debug CoreKit | An optimized external consumer compiled and called `applyingHermeticServiceOverlay` | Wrap the entire public overlay extension in `#if DEBUG` | A Release CoreKit consumer first compiles the approved diagnostic API, then separately fails closed unless the overlay is absent with the expected compiler diagnostic |
| PurchaseFlow assertions overstated their proof | The old upgrade check tolerated no matching entry, discarded the boolean, and used broad label predicates/fallbacks | Add a stable Settings upgrade identifier, assert exact Settings navigation, exact upgrade entry, and exact paywall-shell destination | All six PurchaseFlow tests pass, including the three exact Settings/upgrade/paywall-shell checks; comments explicitly exclude product loading, localized price, purchase initiation/completion, backend verification, entitlement activation, and restore success |

### Implemented behavior

- `AppConfig` retains whether each required Info.plist key was absent, while preserving its existing string API.
- Validation covers `API_BASE_URL`, `COGNITO_REGION`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, and `COGNITO_DOMAIN` with typed fields and issue categories.
- Example-domain fragments, explicit template words, unexpanded build settings, and X-filled values are rejected before shape validation.
- Public API URLs require HTTPS; `localhost`, `127.0.0.1`, and exact bracketed IPv6 loopback `[::1]` remain valid HTTP development endpoints. Arbitrary bracketed/nonloopback IPv6 hosts, user info, queries, and fragments are rejected.
- Cognito region, pool, client, and hostname shapes are checked, including pool-region agreement. A structurally valid standard hosted domain in the exact `<prefix>.auth.<region>.amazoncognito.com` form must also agree with `COGNITO_REGION`; malformed AWS-suffix lookalikes remain malformed, while valid custom domains require no inferred region. Validation is synchronous and performs no DNS or network I/O.
- Invalid validation results contain ordered field/category issues only. Diagnostics store only coarse build identity and service-construction readiness; support code `CF-DEV-CFG-001` is a fixed computed member with no caller-supplied initializer slot.
- `ValidatedAppConfig` is the capability required by `AppModel`; its initializer can no longer read or accept an unchecked configuration.
- `AppBootstrap` validates and conditionally creates `AppModel` once in the app initializer. SwiftUI receives the stored result and cannot recreate the graph during root-view initialization or body reevaluation.
- Invalid configuration routes to a dedicated scrollable root. Debug copy provides local setup guidance; non-Debug copy remains generic. Neither path exposes raw values or product UI.
- The existing deterministic UI harness gets a valid synthetic `.test` configuration only when both `CF_STUB_SERVER=1` and `CF_HERMETIC_TEST_CONFIGURATION=1` are explicit. The Debug-only overlay replaces only the five required API/Cognito values, preserves the supplied monthly, annual, and optional upfront StoreKit IDs, and forces Sentry off. The overlay API is absent from non-Debug CoreKit; auth bypass alone and normal Debug launches cannot activate it.
- A separate Debug-only invalid fixture explicitly keeps Sentry and all three StoreKit IDs empty because validation stops before service construction. Its UI test also enables URL stubbing so a validator regression cannot contact a live service.
- The AppFeature macOS build/test host uses an inert notification authorizer because `UNUserNotificationCenter.current()` traps in a non-application SwiftPM runner. Shipping iOS construction is unchanged.
- Existing mobile maintenance/update configuration remains behind the valid bootstrap and its package tests remain green.

No setup action was added because the root has no safe in-app action that can edit local build configuration. The screen instead gives direct, actionable file guidance.

### Changed files

Configuration and bootstrap:

- `Secrets.example.xcconfig`
- `ChapterFlow/ChapterFlowApp.swift`
- `ChapterFlow/TestSupport/CFAppLaunchSupport.swift`
- `Packages/CoreKit/Sources/CoreKit/AppConfig.swift`
- `Packages/CoreKit/Sources/CoreKit/Config/AppConfigOverlay.swift`
- `Packages/CoreKit/Sources/CoreKit/Config/AppConfigValidation.swift`
- `Packages/CoreKit/Sources/CoreKit/Config/AppConfigurationTypes.swift`
- `Packages/CoreKit/Sources/CoreKit/Config/ConfigurationValueInspection.swift`
- `Packages/CoreKit/Sources/CoreKit/Observability/AppConfigurationDiagnostics.swift`

Application composition and UI:

- `Packages/AppFeature/Sources/AppFeature/AppModel.swift`
- `Packages/AppFeature/Sources/AppFeature/AppRootView.swift`
- `Packages/AppFeature/Sources/AppFeature/ConfiguredAppRootView.swift`
- `Packages/AppFeature/Sources/AppFeature/DebugMenuView.swift`
- `Packages/SettingsFeature/Sources/SettingsFeature/SettingsView.swift`

Tests:

- `Packages/CoreKit/Tests/CoreKitTests/AppConfigValidationTests.swift`
- `Packages/CoreKit/Tests/CoreKitTests/AppConfigOverlayTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/AppModelTestSupport.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/AppModelTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/QuickActionTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/ConfiguredAppRootViewTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/InvalidDevelopmentConfigurationRenderTests.swift`
- `ChapterFlowUITests/ChapterFlowUITests.swift`
- `ChapterFlowUITests/Flows/PurchaseFlowTests.swift`
- `ChapterFlowUITests/Flows/SignInFlowTests.swift`
- `ChapterFlowUITests/Support/AppRobot.swift`
- `Packages/PaywallFeature/Tests/PaywallFeatureTests/StoreKitServiceTests.swift`

CI, verification, and status:

- `.github/workflows/pr.yml`
- `scripts/verify-wp-dev-01-compile-boundaries.sh`
- `docs/ios/DEVELOPMENT_EXECUTION_STATUS.md`

`DebugMenuView.swift` contains only a two-line `#if os(iOS)` guard around the existing iOS-only navigation-title API. This was the minimum adaptation required for the mandated AppFeature host test to compile; it does not alter the iOS UI.

### Toolchain, tools, and disk

| Item | Value/use |
|---|---|
| Xcode | 26.6, build `17F113` |
| Swift | 6.3.3 |
| SwiftLint | 0.65.0 |
| Simulator | iPhone 17 Pro, iOS 26.5, selected by the current CI algorithm |
| Initial free disk | approximately 146 GiB |
| Final free disk | approximately 115 GiB after removing only this worktree's generated shared SwiftPM scratch |
| Second-remediation final free disk | approximately 61 GiB; two generated untracked SwiftPM directories totaling approximately 10.2 GiB were removed before commit |
| Skills | `swiftui-expert-skill`, `swift-concurrency`, `swift-testing-expert`, `mobile-ios-design`, and the GitHub publish workflow |
| Specialized tooling | XcodeBuildMCP session defaults, launch, semantic snapshot, and screenshot; SwiftPM; `xcodebuild`; SwiftLint; local Git; connected GitHub tooling for publication |

No backend search was needed because WP-DEV-01 changes no endpoint, serializer, auth contract, schema, storage, or deployment behavior. No official Apple documentation lookup was required for a new platform API; current SwiftUI, Observation, concurrency, accessibility, and testing guidance from the loaded skills was applied.

### Second-remediation validation evidence at `ee792b1401563b6593f7eb31bab4de4c6abd8ed5`

The original bootstrap evidence remains tied to `53603a2532e8e9ec8b28536009da295b9a1fc522`, and the first remediation evidence remains tied to `8aca1253a3d0ac07f33ec3226d79f3b33cf0dbf8`. The independent verifier evaluated the later evidence head `63cdbb06dd2370a8468729231b08228c7a044ba6` and returned **FAIL** with four P2 findings. The results below were freshly rerun against the exact source recorded by second-remediation implementation commit `ee792b1401563b6593f7eb31bab4de4c6abd8ed5`; this documentation-only successor does not alter compiled sources or tests. Separate independent re-verification remains pending.

#### Focused package tests - PASS

```sh
swift test --package-path Packages/CoreKit
```

Result: exit 0; **147 tests in 26 suites passed**. Coverage includes matching/mismatched standard Cognito hosted-domain regions, valid custom domains, malformed AWS-like domains, twelve API URL cases including exact `[::1]`, value-free reflected/diagnostic output, structurally fixed support-code storage, and an explicit Debug overlay that preserves all three StoreKit IDs while disabling Sentry.

```sh
swift test --package-path Packages/AppFeature
```

Result: exit 0; **67 tests in 18 suites passed**. Invalid bootstrap invoked the graph factory zero times; valid bootstrap invoked it exactly once; 50 repeated SwiftUI body evaluations retained one graph; diagnostics failures did not alter routing. Light, Dark, 320x568, and AX5 render guards passed.

The first AppFeature attempt compiled but its macOS test process trapped when existing AppModel tests reached Apple's process-global notification center without an application bundle. The host-only inert authorizer seam was added; the exact command then passed. This was diagnosed rather than retried blindly.

```sh
swift test --package-path Packages/PaywallFeature
```

Result: exit 0; **161 tests in 21 suites passed**. The strengthened StoreKit configuration test proves the path `AppConfig` source -> hermetic overlay -> validated configuration -> `StoreKitConfig` retains the existing monthly, annual, and optional upfront identifiers. It does not claim product loading or purchase behavior.

#### Exact 17-package CI loop - PASS

The unmodified package list and shared-scratch loop from `.github/workflows/pr.yml` ran with:

```sh
swift test --package-path "Packages/$pkg" --scratch-path "$PWD/.spm-build" --parallel
```

Result: **17 of 17 package targets passed**: Models, CoreKit, Networking, Fixtures, DesignSystem, AIFeature, AuthKit, EngagementFeature, LibraryFeature, NotificationsFeature, OnboardingFeature, PaywallFeature, Persistence, QuizFeature, ReaderFeature, SettingsFeature, and SocialFeature.

An initial sandboxed invocation could not compile any manifest because Swift required `~/.cache/clang/ModuleCache`; it was stopped once the common infrastructure cause was proven. The exact loop was then authorized outside that restriction and passed. The generated shared scratch was deleted afterward; no source, fixture, snapshot, or other worktree was removed.

#### Non-Debug API compile boundaries - PASS

```sh
scripts/verify-wp-dev-01-compile-boundaries.sh
```

Result: exit 0. The script builds CoreKit in Release, type-checks an approved external consumer of `AppConfigurationDiagnosticRecord`, then performs two independent fail-closed negative probes. The overlay probe passed only after the compiler reported `has no member 'applyingHermeticServiceOverlay'`; the privacy probe passed only after the compiler reported `extra argument 'supportCode' in call`. CI now runs the same script with its shared `.spm-build` scratch path. A sandboxed final invocation first failed because Swift could not write its compiler module cache; the exact script was authorized outside that restriction and passed without a source change.

#### Exact Debug iOS Simulator build - PASS

CI parity first copied `Secrets.example.xcconfig` to ignored `Secrets.xcconfig`, then ran:

```sh
set -o pipefail
xcodebuild build \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

Result: exit 0 and `** BUILD SUCCEEDED **`.

#### Exact Release iOS Simulator build - FAILED; full Release-app proof BLOCKED by unchanged, out-of-scope SocialFeature code

```sh
set -o pipefail
xcodebuild build \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

Result: exit 65; three compile tasks exposed eight diagnostics in unchanged starting-head `SocialFeature` code. `FakeSocialRepository` references Debug-only `OwnProfile.preview`, `BadgeItem.previewList`, `ReferralProfile.preview` twice, `PublicProfile.preview`, and `ReadingPair.preview` twice; `ReflectionRowView` references `.cfSpacing6`, also declared inside `#if DEBUG`. `git diff 63cdbb06dd2370a8468729231b08228c7a044ba6 -- Packages/SocialFeature` is empty. The failure was diagnosed once and was not rerun blindly. The authorized task explicitly excluded Social production changes, so the application-wide Release build remains blocked by this pre-existing defect; the independent Release CoreKit consumer above is the scoped proof that the hermetic overlay and caller-controlled support-code APIs are absent.

#### Focused PurchaseFlow/canary evidence - PASS after intentional red proof

On the untouched `63cdbb...` verifier worktree, the former `testUpgradeEntryPointExistsForFreeUsers` passed even after its broad cell query missed because a broad fallback was permitted and the existence result was discarded. During remediation, a temporary bad-root canary made the new strict `goToSettings` assertion fail at the missing exact Settings tab, proving that the helper no longer silently continues. The canary was removed. The final exact navigation, free-user upgrade-entry, and paywall-shell tests then passed as part of the complete nonparallel UI lane below; no intentional failure or test-only source mutation remains.

#### Exact ChapterFlowUITests lane - PASS

```sh
set -o pipefail
xcodebuild test \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination "platform=iOS Simulator,id=<BOOTED_SIMULATOR>" \
  -only-testing:ChapterFlowUITests \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

Final result: exit 0 and `** TEST SUCCEEDED **`:

- `PurchaseFlowTests`: 6 passed;
- `ReadQuizUnlockFlowTests`: 6 passed;
- `SignInFlowTests`: 10 passed, including no-flag, auth-bypass-only, invalid-fixture, and explicit-hermetic configuration paths;
- `SmokeLaneTests`: 2 intentionally skipped because `CF_REAL_API=1` was absent;
- total: **24 executed, 22 passed, 2 skipped, 0 failures**.

Result bundle: `/Users/radinsoltani/Library/Developer/Xcode/DerivedData/ChapterFlow-ebwvjovlsreifdbrgnobxdcedqgf/Logs/Test/Test-ChapterFlow-2026.07.13_06-36-09--0300.xcresult`.

The second-remediation lane passed on its first complete run. No production behavior, timeout, retry policy, skip, or test scope was weakened. `PurchaseFlowTests` proves the fixture-backed app shell, exact Settings navigation, the stable free-user upgrade action, and presentation of the exact Settings-context paywall shell. It does **not** prove StoreKit product loading, localized pricing, purchase initiation or completion, backend verification, entitlement activation, or restore success.

#### Lint and diff - PASS

```sh
swiftlint lint --strict --reporter github-actions-logging
git diff --check
```

Results: SwiftLint exit 0 with **0 violations and 0 serious violations in 737 files**; diff check exit 0. A separate read-only second-remediation review found no actionable P0-P3 findings in the implementation/test/CI diff. This local review does not supersede the independent verifier's FAIL at `63cdbb...` or the pending independent re-verification of the new head.

#### Red reproduction, tool restrictions, and diagnostic retries

- The `[::1]`, caller-controlled support code, non-Debug overlay exposure, and permissive PurchaseFlow behavior were each reproduced against the verifier input before the fixes were accepted.
- The first standalone Swift probe used an invalid top-level filename/path combination; it was corrected before any conclusion was recorded. The corrected probes produced the red evidence above.
- An initial original-test UI invocation selected zero tests because its source had been temporarily renamed during a long-running build. The reproduction was rerun from the untouched detached verifier worktree: the old test passed after the broad cell query missed, a broad button fallback was tried, and the result was discarded. A temporary bad-root canary made the new strict navigation assertion fail as intended; the canary was removed before final validation.
- SwiftPM package and compile-boundary checks initially hit sandboxed compiler-cache permissions. The exact commands were rerun outside that restriction; no source or assertion was weakened.
- A separate read-only reviewer attempted `swift test --package-path Packages/CoreKit --skip-build` only to cross-check the recorded count. Manifest planning exited 1 under the same sandboxed `~/.cache/clang/ModuleCache` restriction; it was not escalated or treated as product evidence because the primary exact CoreKit run had already passed.
- One semantic simulator snapshot returned a tooling translation-object error after the screen was already rendered. An immediate snapshot of the unchanged process succeeded; both the semantic tree and visual capture agreed.
- The Release app failure was diagnosed from the emitted `.dia` diagnostics and starting-head diff. It was not retried or relabeled as a pass.

### Runtime and accessibility evidence

A fresh iPhone 17 Pro simulator on iOS 26.5 was created for the second-remediation matrix, received the exact Debug product, and was shut down and deleted after capture. XcodeBuildMCP semantic snapshots and screenshots produced the following outcomes:

| Launch environment | Verified outcome |
|---|---|
| No test flags | Fail-closed setup root |
| `CF_STUB_SERVER=1` only | Fail-closed setup root |
| `CF_HERMETIC_TEST_CONFIGURATION=1` only | Fail-closed setup root |
| Stub plus hermetic, without auth bypass | Signed-out ChapterFlow auth root with `Continue with Apple`; no setup root or tab bar |
| `CF_INVALID_TEST_CONFIGURATION=1` only | Fail-closed setup root |
| `CF_UITEST_BYPASS_AUTH=1` only | Fail-closed setup root |
| Stub plus hermetic plus auth bypass, covered by the full UI lane | Fixture-backed signed-in shell with tab bar |

Every fail-closed case exposed `invalid-development-configuration`, heading `ChapterFlow Needs Setup`, and exact support label `Support code: CF-DEV-CFG-001`, with no tab bar or login action. The two-flag signed-out case independently proves configuration activation without relying on auth bypass. The all-three-flags UI lane separately proves the signed-in shell.

- The UI uses semantic DesignSystem colors and fonts, a flexible `ScrollView`, no fixed text/control height, heading traits, contained reading order, hidden decorative icons, and text labels in addition to icons/color.
- Render guards covered Light Mode, Dark Mode, 320x568 geometry, and AX5 Dynamic Type. The surface has no motion; the AX5 guard also disables transaction animation, satisfying Reduce Motion without adding a separate animation path.
- XCUITest verified the root, heading, guidance, exact support-code label, absence of tab UI, and absence of login controls. The Settings upgrade action now has a stable accessibility identifier while retaining its descriptive label and hint. VoiceOver order follows source order and `.contain` accessibility grouping; no physical VoiceOver session was claimed.

### Security, privacy, contracts, and migrations

- Invalid state and diagnostics retain no raw AppConfig, URL, Cognito ID, token, DSN, credential, request/response body, or personal data.
- Tests reflect invalid results and records to confirm private URL and identifier strings are absent. They also prove issue categories carry no associated values and the record stores no support-code field.
- The support code is structurally fixed: callers cannot provide arbitrary content through the initializer, valid and invalid records return `CF-DEV-CFG-001`, and the external non-Debug compiler probe rejects a custom value.
- Invalid configuration cannot reach `AppModel`, `AuthService`, `SessionManager`, `APIClient`, analytics transport, StoreKit/entitlements, live repositories, or other network-backed feature services.
- Synthetic test values use reserved `.test` hosts and fake non-production identifiers. They require explicit Debug-only launch environment activation.
- No API contract, model wire shape, persistence schema, migration, deployment order, or rollback mechanism changed. Rollback is a direct revert of the focused bootstrap commit.

### Acceptance and contamination review

| Requirement | Result |
|---|---|
| Five required values typed and validated | PASS |
| Exact bracketed IPv6 loopback `[::1]` accepted; nonloopback/malformed literals rejected | PASS |
| Standard Cognito hosted-domain region agrees with configured region | PASS |
| Placeholder/example configuration rejected | PASS |
| Invalid path creates zero live graphs/services | PASS |
| Valid path creates exactly one graph | PASS |
| SwiftUI reevaluation cannot duplicate graph | PASS |
| Explicit hermetic UI-test configuration only | PASS |
| Hermetic overlay API absent from non-Debug CoreKit | PASS |
| Hermetic overlay preserves three existing StoreKit IDs and disables Sentry | PASS |
| Normal Debug placeholder launch remains invalid | PASS |
| Structurally fixed, privacy-safe deterministic diagnostics | PASS |
| Invalid root accessibility/render matrix | PASS |
| Existing maintenance/update tests | PASS |
| Sign-In, Home, Library, Book Detail, and truthful PurchaseFlow shell/navigation regressions | PASS |
| No Audio or Social file changed | PASS |
| No PR #117 commit cherry-picked wholesale | PASS |
| No release-only configuration or machinery imported | PASS |

The complete diff contains no App Store identity, product/price/subscription-group change, release manifest, export options, waiver, attestation, signing, provisioning, TestFlight detection, production Sentry requirement, deployment logic, Audio change, or Social change. No PaywallFeature implementation, StoreKit catalog, product identifier, or transaction behavior changed. A test-only assertion proves existing identifier propagation; the XCUITest purchase lane is limited to the fixture-backed shell, exact Settings navigation, upgrade entry, and paywall-shell presentation.

### Remaining limitations and prohibited-action confirmation

- Live Cognito/SIWA, authenticated deployed-backend behavior, account switching, real StoreKit transactions, StoreKit Sandbox, physical-device installation, and production configuration were **not run** and are not claimed.
- The two optional real-API smoke tests were **skipped by design** because no `CF_REAL_API=1` authorization or token was supplied.
- The unsigned Release application build **failed** on eight pre-existing `SocialFeature` Debug-preview references. That package is unchanged from `63cdbb...`, Social production work was explicitly out of scope, and the failure remains an application-wide Release-build blocker rather than a WP-DEV-01 pass.
- No physical VoiceOver, Reduce Transparency, or signed-device session was run; the deterministic semantic and render evidence above is the scoped accessibility proof.
- The setup root still contains hard-coded English development guidance. Localization is deferred to `WP-L10N-01`; this remediation intentionally did not broaden into a localization rewrite.
- Independent verification remains **FAIL at `63cdbb...`** until the new draft PR head receives a separate read-only re-verification. Local validation and local read-only review are not substitutes for that checkpoint.
- PR #119 remains draft and unmerged. No merge, deployment, App Store Connect action, TestFlight action, Sandbox purchase, signing/provisioning change, production-data action, PR #117/PR #120 mutation, backend PR #402/backend change, or unrelated-user change occurred.

---

## WP-CONTRACT-01 final merged-backend integration — 2026-07-14

### Revisions and integration shape

- Current iOS `main`: `16d9b17c2743f40656ac9617af13eece51e1afc4`.
- Existing iOS PR #120 remote head before finalization: `da70b02e73c67cf9a19962edacc4a7a5ff1b7a8b`.
- Prepared iOS source snapshot: `8fec3a3a2ae21af87a799334949491fd90d9af72`.
- Prepared iOS manifest commit and temporary-branch head: `5dec724e77f04e91aecf321c60280bdbbf71a083`.
- Scanner remediation: `7f9080fb503c3ad9a0010af0f7744cfd21cd288e`.
- Backend PR #402 merge method: squash.
- Backend `main` and exact latest contract-changing commit:
  `6a792cf2572f585e56ce5dbb181307955c1896a8`.
- The backend squash commit and former PR head `0ee789788c155505e039651b19483e37b41d28ff`
  have the same tree; the old PR head is intentionally not used as merged provenance.
- Backend push-to-main CI run `29300772440` passed all 11 jobs in 3m58s.

The local `codex/wp-contract-01` branch already equaled the verified temporary source-snapshot
head, so `git merge --ff-only origin/codex/wp-contract-01-source-snapshot` completed as
`Already up to date`. No rebase, squash, reset, or history rewrite occurred.

### Final generated evidence

The final overlay was generated twice and checked from a clean detached backend checkout at
`6a792cf2572f585e56ce5dbb181307955c1896a8` with:

- `sourceRevision`: `6a792cf2572f585e56ce5dbb181307955c1896a8`;
- `sourceRevisionPhase`: `merged_backend`;
- `trustedMainRef`: `refs/remotes/origin/main`;
- `trustedMainRevision`: `6a792cf2572f585e56ce5dbb181307955c1896a8`;
- overlay SHA-256: `c004d42cdcb0e60e4acc5f0d94c0fb349bef6261a029348ccf952edf993dfd5f`;
- backend input-tree SHA-256: `2f9caf4485a4f7af52dcbeaebe0b00100a458bdcfcfa285d839955a916c5bf98`;
- generator-tree SHA-256: `50c49dff44d58fc2cc0c36cd58826987e5370953a6db4f9c388a92b563d4b056`;
- manifest SHA-256: `03a2b3295fc6dd97dc4f06c6a1189c6b70924424cb056157adf4839ee1b0fd05`;
- relational-record SHA-256: `03103dcada4b7ae3ed2763372dda873aa504a75c18ae4553e91cc71f17007a78`;
- iOS input-tree SHA-256: `9f1b7285c945cee0f457535066fd7be664b7d28973ffb71b13ac67889c97377e`.

The iOS-owned manifest remained byte-identical to the merged backend copy and still records
`iosSourceRevision = 8fec3a3a2ae21af87a799334949491fd90d9af72`. It covers 584 exact Git-object
inputs: 582 production Swift sources plus the inventory mapping and generator.

Inventory and coverage remain **83 operations / 93 producers / 29 matrix rows / 93 relations**,
**0 full / 60 partial / 23 blocked**, **6/93** exact factory proof, and **24/60** production
success-decoder/cache proof. Authority remains 51 structural proofs, four production-consumer
deletion tests, and one blocked/unproven server decision. `quiz-submit.post` remains fail-closed;
no success fixture or local grade/unlock result was added.

### Source-proven request corrections

The six parameterized factory cases prove the four existing corrections without changing public
Swift signatures:

1. `getBook` and `getManifestForDownload` are public `GET` requests.
2. `postTier` sends `GET` without a body.
3. `getAudioPlan` and `getAudioPlanFreshURLs` send ordered `mode=plan`.
4. `postOnboardingProgress` sends `PATCH`.

### Focused local validation

- Python compilation: passed with an external bytecode cache.
- iOS inventory/scanner suite: **66/66 passed** in 58.822s.
- Backend canonical/provenance suite through refresh: **53/53 passed**; deterministic double
  generation and the identical `--check` command passed.
- Backend branch/normal-merge/squash-merge provenance canaries: passed.
- Models: **180 tests in 66 suites passed**.
- Networking first full run: **failed with three issues** because
  `expectedIOSInventoryRevision` still named the pre-snapshot revision `0b0f6bc...`.
- Focused red reproduction: the inventory-manifest test failed at its two stale equality checks.
- Remediation: updated only that test-evidence constant to `8fec3a3...`.
- Focused inventory regression: passed; corrected endpoint factories: **6/6 passed**.
- Networking final run: **67 tests in 6 suites passed**.
- Shell syntax, ShellCheck, and contract-drift YAML syntax/shape validation: passed.
- Strict SwiftLint: **0 violations and 0 serious violations in 742 files**.
- The first SwiftPM attempts were blocked by the outer sandbox's nested `sandbox-exec`; the exact
  commands were rerun once outside that restriction and produced the results above.
- The first refresh attempt was blocked by the outer sandbox denying the `tsx` IPC socket; the
  exact command and its `--check` form passed outside that restriction.
- The first SwiftLint attempt found zero violations but could not save its cache; the exact command
  then passed outside that restriction.

The full package matrix, app build, and XCUITest were intentionally not run locally. Exact-head
GitHub workflows are the broad regression executor and their terminal results are recorded in PR
#120 after the single final push.

### Remaining limitations and prohibited-action confirmation

All 23 blockers retain their prior closed owners and dependencies. No blocker was reclassified or
fixed in this finalization. No deployed-backend compatibility, production request, physical-device,
real-API, StoreKit, signing, TestFlight, App Store, deployment, release, or migration claim is made.
PR #120 remains draft and must not be merged as part of this task. PR #117, backend PR #401,
branch protection, CI architecture, release state, and unrelated user work remain untouched.

---

## WP-CONTRACT-01 closeout and WP-CONTRACT-01F blocked local implementation — 2026-07-14

The draft-state statement above is retained as historical evidence from the finalization run. PR
#120 subsequently merged through real merge commit
`72d4a1a90a6f360479dfccfda5cafd7f193af7b5`, with parents
`16d9b17c2743f40656ac9617af13eece51e1afc4` and
`04781abf338928003682e1fa2754e50490c5db25`. The merge commit and PR head share tree
`c6319d52967d3e2fa97e12b4c7aecb7b6c58deb0`. WP-CONTRACT-01 is therefore closed as a real
merge, not a squash, rebase, or branch-head inference.

Its evidence remains unchanged: 83 operations, 93 producers, 29 matrix rows, 93 relations, 0 full,
60 partial, 23 blocked, 6/93 exact request-factory proofs, and 24/60 production success-decoder or
cache proofs. The committed manifest still pins source snapshot
`8fec3a3a2ae21af87a799334949491fd90d9af72` and remains byte-identical to the backend copy from
merged backend source `6a792cf2572f585e56ce5dbb181307955c1896a8`. Neither source merge is deployment evidence.

WP-CONTRACT-01F changes only the ongoing iOS drift gate. Its local implementation preserves exact
historical Git-object reproduction and backend identity while comparing the current worktree by
all-source producer and request semantics, so unrelated Swift bytes no longer force a
cross-repository repin. It does not change production Swift, backend runtime source, the historical
generator or source mapping, the generated manifest, bundle, or backend manifest copy, coverage,
blocker ownership, CI v2 architecture, release state, or frozen PR #117.

The focused P1 red was exact and pre-fix: a generic
`typealias Factory<T> = @Sendable () -> T` with stored `Factory<Endpoint>` was accepted
(`AssertionError: DriftError not raised`; one test in 58.653 seconds). The remediation added a
bounded deterministic masked-source type parser and recursive alias resolver with positional
substitution, chains, scope/visibility/shadowing, and fail-closed cycle, arity, depth, node, token,
ambiguity, and incomplete-proof diagnostics. Producer discovery now independently scans
file/type-scope callables, computed properties, and stored initializer normal-result/escape flow,
including direct factory references and Endpoint-bearing return carriers.

The pre-review implementation passed 132/132 incremental canaries; the unchanged historical
generator/scanner passed 66/66. Two authorized remediation passes expanded the current incremental
suite to 153 tests and made all original and pass-1/pass-2 P1 reproductions behave as intended.
Targeted final-pass tests and the unmodified production tree remained green at 83 operations, 93
producers, 29 matrix rows, and 93 relations. That is not a completion claim: the final independent
review found one unresolved P2 false positive after the second and final remediation pass.

The remaining valid Swift form binds `let make = Endpoints.getBooks` locally and returns
`send(make()) -> Response`. The local factory is nonescaping and direct-call-only, but the current
return-expression heuristic rejects the enclosing `debug() -> Response` as an unexpected Endpoint
producer. The equivalent direct `send(Endpoints.getBooks())` passes. Because the remediation ceiling
is exhausted, the full final 153-test run was stopped, WP-CONTRACT-01F is **NOT MERGE READY**, and no
commit, push, draft PR, or GitHub workflow run was created.

### Superseding owner-authorized WP-CONTRACT-01F correction — 2026-07-14

The blocked checkpoint above remains historical evidence. The owner subsequently authorized one
final architecture correction and superseded the prior two-pass ceiling. The corrected boundary no
longer treats a function-local alias such as `let make = Endpoints.getBooks` as an independent
producer. A use is direct-call-only when the alias is the immediate syntactic callee, even inside a
nested call or ancestor return expression. Bare return/argument/assignment/storage,
collection/tuple placement, captured closure use, and unsupported ambiguity remain fail-closed
escapes. Enclosing declared/resolved Endpoint-carrying callables and file/type-scope generic stored
aliases remain producer candidates.

The exact async `return try await send(make())` sample typechecked, then reproduced the pre-fix
unexpected-producer rejection (`1 test in 21.542 seconds`). After replacing the return-text
heuristic with a bounded use-role classifier, that canary passed (`1 test in 22.935 seconds`; 23.08
seconds wall time). Five pure role tests complete in 0.001 seconds and cover immediate invocation,
parentheses, nesting, repetition, branches, bare values, arguments, outward storage, collections,
tuples, closure capture and ambiguous call-role syntax. A separate concrete local Endpoint value
keeps its existing result-flow proof instead of being treated as a function value.

The final locked verifier SHA-256 is
`20fac4a9dc26736612e5a96b1de84e57c58d7aa1d4a45435f1c5749fdfb59c58` under policy schema v2.
Final local results are:

- incremental drift: **162/162 passed in 2,680.016 seconds**;
- historical generator/scanner: **66/66 passed in 50.254 seconds**;
- production semantics: **83 operations / 93 producers / 29 matrix rows / 93 relations**, plus 584
  exact historical Git-object inputs, in 26.11 seconds;
- backend provenance canaries: pass;
- exact merged-backend `refresh-fixtures.sh --check`: pass against clean
  `6a792cf2572f585e56ce5dbb181307955c1896a8`; **53/53** backend tests passed and both generated
  overlays matched;
- Python compile, policy lock and stale-digest rejection, shellcheck, Bash syntax, actionlint,
  changed-YAML parse, strict SwiftLint (0 violations in 742 files), diff and conflict guards: pass.

The single fresh read-only scope-frozen reviewer returned **CLEAR** with no valid P0/P1/P2 finding.
Its novel exhaustive enum-switch consumer used both `builder()` and `(builder)()` and passed full
semantic comparison. Its bare `return builder` escape was rejected, the generic file/type-scope
producer remained blocked, mapped method drift remained blocked, the stale policy digest remained
blocked, and workflow triggers and unconditional checks remained fail-closed.

No production Swift, backend source, historical manifest, generated bundle, backend manifest copy,
source mapping, historical generator/test, schema, migration, secret, deployment, release, App
Store, TestFlight, branch-protection, PR #117 or unrelated-user state changed. This status record is
prepared before publication and therefore makes no draft-PR or exact-head GitHub conclusion; those
checks remain mandatory for the final merge verdict. WP-CONTRACT-01F remains unmerged.

---

## WP-BOOT-01A deterministic launch and storage health — 2026-07-14

**Phase:** A, local implementation only

**Branch/worktree:** `codex/wp-boot-01a-launch-storage-health` at
`/private/tmp/Chapterflow-IOS-wp-boot-01a`

**Base:** `5df81f7722e856130854add1590585acddb9d6e7`

### Outcome

The launch path now renders a lightweight preparing surface before persistent storage opens. An
`@MainActor @Observable` coordinator owns one generation-tagged bootstrap task and publishes one of
five closed states:

| State | User-visible behavior | Live graph |
|---|---|---:|
| preparing | Lightweight launch surface | 0 |
| ready | One normal `AppRootView` | 1 |
| invalid configuration | Existing WP-DEV-01 fail-closed surface | 0 |
| storage unavailable | Retryable recovery surface, support code `CF-BOOT-STORAGE-001` | 0 |
| session configuration failed | Retryable recovery surface, support code `CF-BOOT-SESSION-001` | 0 |

The default persistence loader opens the existing `PersistenceController` migration plan and the
required download directory asynchronously across Swift's `@concurrent` boundary. It returns both
resources as one required value. `AppModel` therefore receives valid, non-optional persistence for
annotations, sync, downloads, and reviews only after storage and minimal session configuration
succeed. Production has no in-memory fallback, alternate directory, automatic deletion, or reset.

Repeated starts while active or ready are idempotent. Explicit retry replaces only a failed attempt,
increments its generation, and synchronously returns to preparing. Cancellation is not rendered as
failure, and a late completion from a cancelled or superseded generation cannot publish a graph or
replace newer state. Long-lived entitlement, MetricKit, session/background registrations, remote
configuration, analytics, push routing, and intent startup occur only after their required ordering
point and are individually idempotent.

The focused UI harness can select hermetic storage only when both the existing explicit stub-server
flag and hermetic-configuration flag are present. That factory is compiled under `#if DEBUG` and is
absent from non-Debug builds; it is a deterministic test dependency, not a recovery fallback.

### Validation and remediation evidence

- Persistence package: **PASS**, 100 tests in 31 suites.
- AppFeature package: **PASS**, 76 tests in 18 suites. This includes 10 bootstrap-coordinator tests
  and 8 deterministic failure/configuration render tests.
- CoreKit package: **PASS**, 147 tests in 26 suites.
- Focused bootstrap XCUITests, initial run: **FAIL**, 2/4 passed. Both session-failure and
  storage-retry cases reached the storage recovery surface because an unsigned Simulator process
  could not open production App Group storage.
- Single focused remediation: add an explicit DEBUG-only hermetic persistence dependency behind the
  paired test flags; no production fallback behavior changed.
- Focused bootstrap XCUITests, final run: **PASS**, 4/4 on iPhone 17 Pro, iOS 26.5. Preparing,
  storage failure/retry, session failure, and invalid-configuration precedence all passed.
- Unsigned Debug generic iOS Simulator build: **PASS**, `** BUILD SUCCEEDED **`.
- WP-DEV-01 non-Debug compile boundaries: **PASS**; both hermetic overlay and caller support APIs are
  unavailable outside Debug.
- Strict SwiftLint: **PASS**, 0 violations and 0 serious violations in 746 files.
- Incremental contract semantics: **PASS**, 83 operations, 93 producers, 29 matrix rows, and 93
  relations. Bootstrap changes require no contract repin.
- `git diff --check`: **PASS** before the final documentation update and required again before the
  local commit.

The isolated worktree uses an ignored placeholder `Secrets.xcconfig` copied from the committed
example solely for compile parity. Live authentication, deployed-backend integration, signed-device
launch, and production configuration were not tested or claimed. No schema, migration plan, API,
backend, authentication method, navigation architecture, entitlement authority, or release
contract changed. Rollback is a normal revert of the local WP-BOOT-01A commit(s); existing durable
data and the V8 migration plan are unchanged.

The recovery surfaces use heading traits, logical reading order, flexible vertical layout, semantic
system colors, and fixed privacy-safe support codes. Deterministic render coverage includes Light
and Dark Mode, AX5 Dynamic Type, and reduced animation. Raw storage/session errors, paths, store
names, SDK messages, identifiers, tokens, and private URLs are discarded before state publication.
No physical VoiceOver or reference-device performance capture was run. The performance result is
architectural—the first frame no longer waits on store opening—not a claim that the 1.5-second
device budget is measured.

### Deferred to WP-BOOT-01B

- Cold/warm privacy-safe launch signposts and Instruments measurements on reference and older
  supported physical devices.
- Historic migration fixtures and protected-data-unavailable, disk-full, migration-failure, and
  corrupt-store recovery taxonomy without silent reset.
- A product decision on whether safe public browsing can operate independently of private durable
  storage.

The single mandatory fresh fixed-checklist read-only reviewer returned **CLEAR**, with no valid
P0/P1/P2 finding. The resulting local head is recorded in the Phase A handoff. Nothing in this
local phase is pushed or published.

### Phase B rebase and pre-publication evidence — 2026-07-14

The owner authorized Phase B after CI Stage B completed. The delegated checkpoint contained one
hyphen in place of a hexadecimal character; a fresh fetch resolved it unambiguously to current
`origin/main` at `0830ba198d9271f7354f4f5d494d67fad1a478c1` (`WP-CI-02: Make CI v2
authoritative and retire duplicate CI (#123)`). The Phase A commit rebased onto that exact revision
without conflict or manual resolution. The rebased implementation head before this evidence-only
documentation successor was `84bd8a267d16887d1584156f6d9f09fecb17bf79`.

The current authoritative pull-request workflow is `.github/workflows/pr-v2.yml`, named
`CI — Required`, with aggregate check `CI / Required`. `.github/workflows/pr.yml` is now the
manual-only legacy fallback and is not treated as a required automatic lane.

Every bounded local gate was rerun after the rebase:

- Persistence: **100 tests in 31 suites passed**.
- AppFeature: **76 tests in 18 suites passed**.
- CoreKit: **147 tests in 26 suites passed**.
- Focused bootstrap XCUITests: **4/4 passed**, 0 failed, 0 skipped, on iPhone 17 Pro with iOS 26.5.
  The selected classes cover preparing, storage failure/retry, required-session failure, and invalid
  configuration precedence. Xcode emitted existing test-target actor-isolation warnings, including
  the shared harness; no warning was suppressed and no XCTest-wide migration was added to this
  bounded bootstrap package.
- Unsigned Debug generic iOS Simulator build: **PASS**, exit 0 and `BUILD SUCCEEDED`.
- WP-DEV-01 non-Debug compile boundaries: **PASS**.
- Strict SwiftLint: **PASS**, 0 violations and 0 serious violations in 746 files.
- Incremental native contract semantics: **PASS**, 83 operations / 93 producers / 29 matrix rows /
  93 relations; no contract repin is required.
- Rebased diff/conflict guard: **PASS**.

This pre-publication record makes no exact-head GitHub CI or merge claim. Those conclusions require
the draft PR, terminal required checks on its exact head, the ready-state transition, squash merge,
and post-merge main CI. No backend, release, App Store, TestFlight, signing, deployment, PR #117, or
unrelated user state changed during the rebase and local revalidation.

---

## WP-BOOT-01B storage recovery, migration confidence, and launch evidence — 2026-07-14

**Phase:** local implementation and pre-publication evidence

**Branch/worktree:** `codex/wp-boot-01b-storage-recovery` at
`/private/tmp/Chapterflow-IOS-wp-boot-01b`

**Exact base:** `6bfa34160f1511e89f7ed2c182830bf8a60d4373`, merged WP-OBS-01A on current
`origin/main` at task start

### Outcome and recovery contract

WP-BOOT-01B preserves the deterministic asynchronous bootstrap from WP-BOOT-01A and closes its
remaining storage-recovery ambiguity. Raw persistence errors are discarded at their owning
boundaries and bootstrap publishes only this value-free taxonomy:

| Category | Fixed support code | User behavior | Automatic mutation |
|---|---|---|---|
| protected data unavailable | `CF-BOOT-STORAGE-PROTECTED-001` | wait surface; no retry control | resume the same bootstrap generation once after protected data becomes available |
| persistent-store open or migration | `CF-BOOT-STORAGE-STORE-001` | explicit retry surface | none |
| required file store | `CF-BOOT-STORAGE-FILES-001` | explicit retry surface | none |
| conservative unavailable | `CF-BOOT-STORAGE-UNAVAILABLE-001` | explicit retry surface | none |

The protected-data path registers once for UIKit's protected-data-available notification and then
rechecks availability to close the registration race. Cancellation removes the observer. One
coordinator owns both the storage task and wait task; generation checks prevent stale callbacks,
repeated notifications, coordinator deallocation, or cancellation from publishing a second graph.
A lock transition during persistence loading returns to the protected-data wait state instead of
being mislabeled as corruption or migration failure.

Production has no automatic store deletion, reset, in-memory fallback, alternate directory, or
silent recovery. The legacy destructive recovery helper is Debug-only test infrastructure and raw
errors, paths, store names, identifiers, configuration values, and private data do not enter
published state, support codes, or signpost metadata.

### Migration and instrumentation evidence

The production V8 schema and seven-stage migration plan are unchanged. Tests now construct one
exact SwiftData store for every declared historical schema V1 through V7, seed a durable
`CachedKeyValue`, and reopen each store through `PersistenceController.makeDefault` and the
unchanged production migration plan. The matrix asserts exact V1-through-V8 schema coverage,
exactly seven adjacent stages, preservation of the seeded record, and current-model
`CachedAskThread` writability after every migration.

Fixed-name `OSSignposter` events cover bootstrap start, first launch view availability,
protected-data wait/resume, persistence start/end, required-session start/end, ready, and the four
fixed storage-failure outcomes. Events carry no dynamic metadata. The injected test recorder proves
the valid phase order and proves recorder failure cannot block launch. The unsigned Simulator
placeholder-configuration path emitted fixed `BootstrapStarted`, `InvalidConfigurationFailed`, and
`FirstLaunchViewAvailable` events with empty metadata.

### Validation and one review-remediation cycle

- Persistence package: **PASS**, 103 tests in 31 suites, including all seven exact historical-store
  migrations and both persistence-stage failure classifications.
- AppFeature package, final post-review run: **PASS**, 84 tests in 18 suites. Coverage includes the
  closed taxonomy, unexpected loader cancellation, one-shot protected-data recovery, a mid-load
  lock transition, stale-callback rejection, coordinator deallocation, privacy-safe support codes,
  deterministic phase order, and non-blocking instrumentation failure.
- CoreKit package: **PASS**, 156 tests in 28 suites.
- Focused bootstrap XCUITests, initial run: **FAIL**, 4/5 passed. The new protected-data wait surface
  recovered before XCUITest completed accessibility setup because its Debug-only availability
  transition was two seconds.
- Focused remediation: extend only that deterministic Debug transition to eight seconds; no
  production behavior or timeout changed.
- Targeted protected-data XCUITest after remediation: **PASS**, 1/1, 0 failed, 0 skipped, on iPhone
  17 Pro Simulator with iOS 26.5. It proved the distinct wait surface, absence of retry/product UI,
  and automatic transition to ready.
- Unsigned Debug iOS Simulator build: **PASS**. Five pre-existing warnings remain; no warning was
  hidden or weakened.
- WP-DEV-01 non-Debug compile boundaries: **PASS**; Debug bootstrap injection remains unavailable in
  non-Debug compilation.
- Strict SwiftLint: **PASS**, 0 violations and 0 serious violations in 753 Swift files.
- Incremental contract semantics: **PASS**, 83 operations / 93 producers / 29 matrix rows / 93
  relations; no contract repin is required.
- Privacy-safe signpost query on the unsigned Simulator: **PASS** for the exercised invalid-
  configuration path. The abandoned local `xctrace` attempt produced no usable capture and is not
  treated as evidence.
- Final `git diff --check` and exact-head publication checks remain required after this documentation
  update.

The single fresh fixed-checklist reviewer found four actionable lifecycle/evidence issues: a
transparent root lifecycle boundary, observer cancellation on coordinator deallocation, bootstrap
start recorded after configuration validation, and a non-scrollable AX5 wait surface. One bounded
remediation cycle moved lifecycle ownership to a stable root, added deterministic deallocation
coverage, corrected phase ordering, and made the wait surface scrollable. The same reviewer then
returned **CLEAR**, including the novel deallocation mutation, with no remaining P0/P1/P2 finding.

### Boundaries, accessibility, and rollback

Protected-data and storage recovery surfaces use semantic system styles, heading traits, logical
reading order, fixed support codes, flexible layout, and a scroll container for AX5 Dynamic Type.
Render coverage includes Dark Mode, AX5, and reduced animation. VoiceOver was not exercised on a
physical device.

No signed-device, cold/warm reference-device, or older-device performance capture was run, so the
1.5-second launch budget is not claimed. Live authentication, deployed-backend integration, and
production configuration were not tested. The worktree's ignored `Secrets.xcconfig` contains only
example placeholders for compile parity.

No schema, migration stage, API, backend, authentication, navigation, entitlement, CI, release,
App Store, TestFlight, deployment, PR #117, or unrelated user state changed. Rollback is a normal
revert of the WP-BOOT-01B commit; existing V8 data and its production migration path are unchanged.
This pre-publication record makes no pull-request, exact-head GitHub CI, merge, or post-merge-main
claim.

---

## WP-ID-01A account context, session scope, and deterministic sign-out — 2026-07-15

**Phase:** local implementation, integrated validation, and the fixed-checklist independent review
are complete; publication and merge are pending

**Branch/worktree:** `codex/wp-id-01a-session-scope` at
`/private/tmp/Chapterflow-IOS-wp-id-01a`

**Base and current committed HEAD:** `2a8b93ff2512027cbbf32402f7a037db3966b8fd`

### Current local outcome

The uncommitted local change set introduces an immutable `AccountContext` only after
`SessionManager` has produced a nonempty verified `SessionIdentity`. Its environment and storage
namespaces are opaque and stable, while descriptions and reflection remain redacted. Invalid or
fallback identities cannot construct the context.

`AppModel` now owns one account-lifetime `SessionScope` rather than constructing private services at
process launch. Guest and signed-out states use public catalog/detail facades and construct no
private graph. Repeated notification of the same identity retains the same scope; an account change
invalidates and finalizes the old scope before constructing the new one. Scope construction is
single-flight, cancellation/generation guarded, and a session-scoped API wrapper rejects work before
or after a session boundary when its permit or authoritative identity no longer matches.

The current scope owns account-specific persistence and downloads, private feature repositories,
preferences, audio, StoreKit/entitlement state, notifications/APNs, analytics/reflection-outbox
storage, sync, and background work. Reader, quiz, AI, Library detail/download, notifications,
Social, analytics, and related composition paths receive immutable account identity or an opaque
account namespace; the mutable `UserIdBox` and production `"anon"`, `"local"`, empty-current-user
fallbacks are removed from the guarded private paths.

The sign-out transition is explicit: quiesce the current scope, stop account work and observers,
attempt Cognito sign-out, then finalize/deallocate the scope and clear private presentation only on
success. A failed provider sign-out resumes the exact same still-authorized scope and does not show
false signed-out UI. Preparing, quiescing, and privacy-safe recovery states do not render previous
account content.

### Decision D-05 and persistence boundary

Ordinary sign-out does not purge account-bound unsynced state. Private SwiftData and file resources
use a stable opaque account/environment namespace, preferences and caches use the same ownership
boundary, and a different account cannot open or drain the previous account's resources through the
new scope. The existing V8 schema and migration sequence are unchanged.

Unknown-owner legacy data is not assigned to the current account, cleared as successful work, or
silently deleted. The 01A paths preserve and leave it dormant when ownership cannot be proven. This
is intentionally a retain/quarantine boundary, not a claim that legacy recovery is complete.
Deletion-specific purge remains `WP-ACCOUNT-01` work.

### Integrated local evidence

The following commands and counts were recorded on the integrated uncommitted worktree after the
final source changes. SwiftPM's home-directory caches were unavailable in the managed sandbox, so
package commands used `--disable-sandbox` with module caches redirected under the isolated worktree.
AppFeature received a clean rebuild after a stale incremental artifact exposed the changed
`KeyValueStore` layout.

| Scope | Integrated result |
|---|---|
| CoreKit | **PASS**, 183 tests in 32 suites |
| AuthKit | **PASS**, 70 tests in 11 suites |
| Persistence | **PASS**, 112 tests in 33 suites |
| AppFeature | **PASS**, 111 tests in 19 suites |
| LibraryFeature | **PASS**, 172 tests in 19 suites |
| QuizFeature | **PASS**, 27 tests in 6 suites |
| NotificationsFeature | **PASS**, 211 tests in 23 suites |
| SyncEngine | **PASS**, 30 tests in 7 suites |
| AIFeature | **PASS**, 170 tests in 28 suites |
| ReaderFeature | **PASS**, 184 tests in 23 suites |
| PaywallFeature | **PASS**, 164 tests in 22 suites |
| SocialFeature | **PASS**, 206 tests in 43 suites |
| SettingsFeature | **PASS**, 50 tests in 12 suites |
| EngagementFeature | **PASS**, 344 tests in 56 suites |
| OnboardingFeature | **PASS**, 26 tests in 5 suites |
| Unsigned Debug iOS Simulator build | **PASS**, iPhone 17 Pro / iOS 26.5; ignored example secrets template only |
| Focused hermetic XCUITests | **PASS**, 3 tests: signed-in shell, tab composition, required-session fail-closed surface |
| Repository-wide SwiftLint | **PASS**, strict, 0 violations in 793 files |
| `scripts/verify-wp-id-01a-identity-boundaries.sh` | **PASS**, all 23 mutable/fallback identity and external-process fail-closed boundaries |
| `scripts/verify-wp-dev-01-compile-boundaries.sh` | **PASS**, non-Debug hermetic/support-code APIs remain unavailable |
| Incremental native contract drift verifier | **PASS**, 83 operations / 93 producers / 29 matrix rows / 93 relations |
| `git diff --check` | **PASS** |

Integrated validation corrected two issues without weakening a gate. Concurrent AppFeature tests
exposed shared process-global intent storage, so the hermetic Siri paths now use isolated stores
while production routing retains the production store. The native-contract verifier then exposed
that an analytics refactor had moved canonical send witnesses and mixed a durable queue identifier
into the exact wire shape; the final implementation keeps the wire event unchanged, stores the
durable identifier in a separate wrapper, and preserves canonical single-flight send sites. Strict
lint also drove behavior-neutral companion-file splits for oversized Book Detail and audio types.

The fixed-checklist reviewer then found one P2: sign-out could cancel an optimistic notification
preference save without retaining the pending value. The single bounded remediation stores the
latest value in the existing opaque account `KeyValueStore`, preserves it when transport is
cancelled, and quarantines uncertain delivery from automatic replay even when that same account scope
returns. This prevents an accepted remote write from racing a later replay without delaying ordinary
sign-out or changing the backend contract. Controlled-delivery regressions prove that B cannot see or
drain A's retained value, rapid updates reach the server in order during one active scope, and an
uncertain A value stays durable but unsent until the deferred 01B recovery path can reconcile it. This
adds a `NotificationsFeature` dependency on the existing `Persistence` package; it adds no schema,
journal, endpoint, or server-contract change.

The final fixed-checklist review is **CLEAR** with zero remaining P0/P1/P2 findings. Publication,
exact-head GitHub CI, and post-merge-main CI remain pending. The XCUITest harness exposes one fixed
synthetic identity, so exact hermetic A-to-B switching is proven by AppFeature integration tests
rather than claimed as XCUITest coverage. No signed-device two-account claim is made.

### Deferred to WP-ID-01B and unchanged boundaries

- Migrate or expose recovery for legacy persisted rows whose owner cannot be proven; keep current
  ownerless data preserved until that policy is implemented.
- Bind and migrate App Group, widget, Share/Action extension, and other external-process artifacts
  with a proven opaque owner before importing, clearing, or replaying them.
- Complete signed physical-device two-account, background transfer, protected-data, APNs, widget,
  and extension evidence, plus any remaining external-process storage hardening.
- Add a durable account-owned APNs unregister retry for the case where provider sign-out succeeds
  while the unregister request is offline or no longer authorized. This slice clears local
  registration state and attempts unregister during quiesce, but it does not claim that a failed
  remote request proves zero residual server registration.
- Complete recovery/discard UX for retained pending work in coordination with `WP-SYNC-01`; do not
  introduce a second mutation journal in this package.

This slice changes no backend source, endpoint contract, retry policy, mutation semantics,
navigation architecture, release configuration, signing, App Store/TestFlight/deployment state, or
frozen PR #117 state. The primary checkout and unrelated user work remain untouched. This local
record makes no commit, push, pull-request, exact-head CI, merge, or post-merge-main claim.

---

## WP-SYNC-02A quiz draft persistence and canonical submit — 2026-07-17

**Phase:** local implementation, merged-backend contract refresh, focused validation, and fixed
count-gate correction are complete; iOS publication and merge are pending

**Branch/worktree:** `codex/wp-sync-02a-quiz-draft-submit` at
`/private/tmp/Chapterflow-IOS-wp-sync-02a`

**Base and pinned history:** iOS `main` is still
`2f92bbf507268330ed31c8c819aabdc3b1f5aec8`; product/source commit
`c71cdfb3c0a26c8d7c2cc8bf6ab931a498123c86`, source snapshot
`32b282a64914caadfab90cebce383f276b7954cd`, and manifest commit
`f224a6153a73b94ebe11289a28a4b09c90c2149e` remain in order and unrewritten.

### Current local outcome

Quiz answers are saved as an account/book/chapter-scoped draft. An offline submit confirms only that
the draft is saved; connectivity changes never auto-submit or locally grade it. A later explicit
submit uses the server attempt number and ordered `responses` containing `questionId` plus
`selectedChoiceId`. Ordinary failure retains the exact draft. A stale-attempt response refreshes
once, never resubmits, and restores answers only when attempt and question identity still match.

The obsolete quiz sync endpoint is removed. Legacy `.quizSubmit` pending mutations are rejected as
unsupported before payload decoding or transport, so no retained legacy shape can become an
automatic replay. The server remains authoritative for correctness, pass state, cooldown, and
unlock behavior.

The effective Package `Sources`/`Tests` diff is exactly 16 files, including the two reserved
Networking contract-test slots. Existing persistence and live-repository regressions were
consolidated into the changed QuizFeature test file to preserve that cap; strict lint required no
new suppression or threshold change.

### Merged-backend contract and provenance

Backend contract PR #408 was squash-merged. The exact contract-changing backend `main` revision is
`04e0ae50b4c1f1722b33a6501e03b79bc8894112`; its post-merge CI completed successfully. Refresh and
`--check` used a clean checkout at that revision and the trusted ref `refs/remotes/origin/main`.

The deterministic bundle reports **83 operations / 92 producers / 29 matrix rows / 92 relations**,
with **61 partial / 22 blocked** operations. `quiz-submit.post` is partial and has one online
producer. Its idempotency class remains unknown and explicitly does not claim replay idempotency or
a deployed backend revision.

The separately collected iOS inventory remains pinned to source snapshot
`32b282a64914caadfab90cebce383f276b7954cd`. Its manifest SHA-256 remains
`fc0daed99b0115bee380cd92f5767caf02bdee39e50971a3c141e0c7f8dc012b`; the refreshed iOS manifest is
byte-identical to the merged backend copy. Two overlay generations were byte-identical.

### Integrated local evidence

| Scope | Integrated result |
|---|---|
| Models | **PASS**, 185 tests in 67 suites |
| Networking | **PASS**, 96 tests in 6 suites |
| Persistence | **PASS**, 113 tests in 33 suites |
| SyncEngine | **PASS**, 44 tests in 8 suites |
| QuizFeature | **PASS**, 37 tests in 8 suites after behavior-preserving test consolidation |
| Focused relaunch/draft/explicit-submit test | **PASS**, 1 test in 1 suite |
| Native inventory generator tests | **PASS**, 66 tests |
| CI workflow tests | **PASS**, 48 tests |
| Merged-backend fixture refresh plus `--check` | **PASS**, deterministic 83/92/29/92 and 61/22 output |
| Unsigned Debug iOS Simulator build | **PASS**, generic iOS Simulator destination |
| Repository-wide SwiftLint | **PASS**, strict, 0 violations in 800 files |
| `git diff --check` | **PASS** |

The build emits one pre-existing `nonisolated(unsafe)` warning in the hermetic UI-test stub route;
this slice does not change that file. The first independent root rerun of two Swift packages was
blocked by the managed sandbox's home-directory module cache; the identical required commands then
passed with cache access. On PR #136, exact-head `CI / Required` then passed all selected jobs at
`18060782a835a5c0a23d5e2936d7b34c80f60364`. Full Contract Drift ran all 162 incremental canaries and
found one stale non-contract mutation target: its Analytics log fixture still searched for `dropped`
while current `main` uses `retained`. The single allowed same-root correction now mutates the exact
unique full log expression; its focused canary passes locally. New exact-head checks remain required.

### Boundaries and remaining publication evidence

Quiz status and offline copy remain textually explicit rather than color-only, and the existing
QuizFeature render guards passed. No signed device, physical-device VoiceOver, deployed backend, or
live-account flow was exercised, and none is claimed. No schema or migration was added.

This slice changes no backend runtime route, auth, storage, deployment, release, App Store,
TestFlight, review-grade, entitlement, or frozen PR #117 state. It does not touch the primary dirty
checkout or unrelated user work. This record makes no green final exact-head, iOS merge, or
post-merge-main claim; those remain required before terminal completion.

## WP-REC-01 recovery baseline and external evidence runner — 2026-07-19

**Outcome:** live ChapterFlow work was re-inventoried from supported local Git/process sources and
paginated GitHub API captures before the recovery baseline was recorded. No historical source was
copied or cherry-picked, no owner work was cleaned, and no product implementation is claimed.

### Revision and evidence boundary

| Scope | Exact revision/state | Evidence type and disposition |
|---|---|---|
| iOS GitHub `main` and package base | `533cf592d88cd85a8e7f363acc05c418626b26b7` | Live GitHub API plus fetched local ref. The only drift from the package's `22da44d27bc18771f4d7db7681e17c10970ccb13` product baseline is the integrated `upgrade/**` plan. |
| Backend GitHub `main` | `3f5ba1ecb570b7e447e40f5ca384925ae5e0fa1f` | Live GitHub API and matching cached ref; static source authority only. |
| Protected backend checkout | `update` at `04e0ae50b4c1f1722b33a6501e03b79bc8894112`, behind remote with untracked owner prompts/plan | Local preservation evidence; `unsafe-to-touch`. |
| Backend deployed revision/environment | Unknown | `blocked-evidence`; source integration is not deployment proof. |
| Frozen iOS PR #117 | open draft, `codex/wp-rel-01` at `7bb9b5a88494027832cfe1553cc3c6c464702ab6`, base `main` | Paginated/API read-only evidence; `frozen`. |

The primary iOS checkout remained branch `Pro` at
`7291e8c3d43b37d3e63f732ffc3a6cc9a8c832d1`. Its default porcelain-v2 status digest is
`e25d240ffa191ef227b5798947d3f59a8dd59789f01cdb31f51a823047d7157d`, tracked binary-diff
digest is `2281f515b42154b92524b39adf3ce2d5814b86212cadf5574207525cf6868d2e`, and governing
`AGENTS.md` digest is `cf9f435745593215cbca036c74fc274b355ee073c48fb6c59c04f72863a0289a`.
These values match the protected planning checkpoint. The exact same three fingerprints are required
again after the package lifecycle. The final lifecycle also records a canonical Git-owner-state
fingerprint before publication and after completion: tracked working-tree and index diff digests plus
every Git-visible untracked regular-file content digest and symlink-target digest, with stable-read
identity and HEAD/status consistency checks. The two privacy-safe JSON inventories must compare
byte-for-byte; untracked path names, file contents, and raw symlink targets are never persisted as
evidence.

During pre-commit verification on 2026-07-19, an external cleanup outside this package removed every
registered `/private/tmp/Chapterflow-IOS-*` directory, the in-progress package claim, and the prior
external evidence root. Git retained the affected worktree registrations as prunable metadata. This
package did not invoke that deletion, repair/prune another package's registration, or claim recovery
of any missing uncommitted owner bytes. WP-REC-01 atomically reacquired only its own package claim,
reconstructed only its package worktree from the retained private candidate lineage, restored it to
the declared path, and reran the repair validation. All earlier deleted evidence is invalidated; final candidate
evidence must be regenerated under a fresh private root and retained through post-merge verification.

### Recovery dispositions

- `unsafe-to-touch`: the dirty primary checkout; dirty S-tier planning and upgrade handoff
  registrations; the WP-ARCH-02 and WP-NOTE-01A registrations whose temporary directories were
  later removed and whose last working state is not reproducible; the prunable onboarding
  registration; the stale protected backend checkout; and every missing, prunable, dirty, foreign-
  registry, live-state-incomplete, or object-unavailable row. Missing paths and unknown state are
  never treated as cleanup permission.
- `active`: this package's isolated `codex/wp-rec-01-recovery-baseline` iOS worktree and the open
  backend PR rows. Separate backend dirty-status and PID captures establish concurrent backend
  activity during the observation window. A clean registry-bound worktree with live open files is
  also `active`; supporting activity captures do not weaken any more restrictive row disposition.
- `novel`: iOS or backend rows whose repository-specific Git relationship proves an ahead commit or
  unique patches. Novel does not mean authorized to copy, merge, or schedule. The missing local
  `codex/wp-onb-01a-recoverable-draft` worktree registration is `unsafe-to-touch` at the worktree
  level; its preserved branch head is used only by the separately stated successor link below.
- `frozen`: PR #117, `codex/wp-rel-01`, and its prunable local registry entry. The missing local
  Git directory is preservation evidence, not authority to repair or prune the frozen registration.
- `merged` or `stale`: historical iOS or backend heads already contained in that repository's exact
  target, tree-equivalent to it, or superseded by an identified integrating commit. Diverged
  histories without proven equivalence—including merge-only content hidden by non-merge patch
  comparison—fail closed as `unsafe-to-touch`. These classifications remain evidence, not packages
  to replay.

The required normalized external inventory keeps the iOS and backend worktree registries and both
repositories' GitHub PR/branch observations as distinct repository-scoped rows even when paths,
branch names, or heads coincide. Each normalized row receives exactly one disposition and exact
head. The inventory binds the backend capture and later classification to the explicitly declared
canonical backend root, exact `github.com/WillSoltani/ChapterFlow` origin, and Git common-directory
identity. Classification uses the iOS and backend object databases separately, verifies each existing
worktree still has the captured canonical path, registry row, HEAD, branch/detached state, and common
Git directory, rejects locked or prunable rows, and rechecks status/open-file liveness and the complete
registry before accepting a permissive disposition. Target objects, status, liveness, or a stable
observation that cannot be proved fail closed. Open backend PR rows are `active`. Successor links are
keyed by repository plus branch, so an identically named backend branch cannot inherit an iOS package
link.

### Evidence-backed successor links

- `codex/wp-onb-01a-recoverable-draft` may inform `WP-ENTRY-01` only for paths that package owns;
  its Persistence and historical UI-test paths are outside that envelope and are not copied.
- The deleted WP-ARCH-02 and WP-NOTE-01A path observations are not reproducible from the retained
  final evidence, so this baseline assigns them no successor link. Historical path-to-package
  suggestions remain unverified leads only and grant no source-transfer or backend-write authority.
- PR #117 has no wholesale successor and remains frozen.

These are scheduling links, not source-transfer permission. Every successor must start again from
its live verified base and declared write set.

### Standard external evidence contract

`scripts/validation/run_evidence.py` is the common stdlib runner for later package rows. It binds an
attempt to sorted repeatable `repository=fullSHA` tuples, stores it append-only under an external
head-set digest, rewrites declared `results/...` outputs outside the source worktree, retains
stdout/stderr/counts/digests, and fails on zero matches, failures, skips, missing/symlink artifacts,
attempt collision, or any changed repository-local `results/` tree. Cross-row inputs must use an
immutable same-package/head-set `attempt://<attempt-id>/results/...` reference whose manifest and
artifact digest still match; directory digests include empty directory names and entry types.
Evidence and lease roots must be outside every Git worktree or bare repository. Evidence directories
and files are private (`0700`/`0600`), controlled path identities are rechecked before finalization,
and arbitrary commands consume a verified private staged copy rather than the mutable source-attempt
path. Direct pytest invocations are selector-bearing and cannot certify an all-skipped run. An owned
command lease remains held through post-command source/results verification and immutable manifest
finalization, then is released in an outer `finally` block. A digest-bound release receipt is written
as the last immutable marker through the verified attempt-directory inode after release; interrupted
body work still produces a failed manifest before propagating the interrupt. Slot and claim inode
identity plus exact attempt metadata bind normal release, and acquisition failures remove only objects
whose ownership was established by that call.

Built-in modes deterministically construct/classify repository-scoped iOS/backend worktrees,
branches, and PRs; fingerprint complete Git-visible owner state; compare exact owner
status/diff/fingerprint/PR #117 projections; and require exact changed-path equality. The unchanged
checked-in validation command shape may obtain its required backend source SHA, canonical checkout,
and immutable backend-worktree capture reference from `CHAPTERFLOW_BACKEND_HEAD`,
`CHAPTERFLOW_BACKEND_REPOSITORY`, and `CHAPTERFLOW_BACKEND_WORKTREES_REF`; the effective two-repository
head set, source reference, root, origin, local checkout state, and targets remain manifest-bound and
validated. Retries are one-level, reasoned, and retain both attempts. Commands matching the checked-in simulator/device trigger set
must hold the single command-scoped capacity lease; same-owner package claims are reentrant and a
foreign collision returns `LOCKED` before execution.

This three-file package changes no Swift/Objective-C source, UI, accessibility behavior, backend
contract, persistence schema, entitlement, configuration, migration, deployment, external service,
App Store, TestFlight, signing, production flag, release evidence, or PR #117 state. Exact-head local
validation, independent review, required GitHub CI, merge ancestry, post-merge CI, protected
fingerprints, and package-owned cleanup remain external lifecycle evidence and cannot be inferred
from this source record alone.
