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
