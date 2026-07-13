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

**Completed:** 2026-07-13, America/Halifax

**Branch:** `codex/wp-dev-01-bootstrap`

**Status:** Implementation and deterministic validation complete; draft-PR publication authorized

### Outcome and revisions

WP-DEV-01 now rejects missing, empty, unexpanded, example, placeholder, malformed, insecure, or internally inconsistent API/Cognito configuration before any live application service graph is constructed. Valid configuration is converted into a typed capability and constructs the graph once in `ChapterFlowApp.init()`, outside SwiftUI body evaluation.

| Scope | Revision/state |
|---|---|
| Authoritative starting revision | `92a5c351a42771f546b3d0e575b3b37a8cbfb588` |
| Final tested implementation revision | `53603a2532e8e9ec8b28536009da295b9a1fc522` |
| Evidence-document revision | Documentation-only successor to the tested implementation; the draft PR head is authoritative |
| Branch base and merge-base with `origin/main` | `92a5c351a42771f546b3d0e575b3b37a8cbfb588` |
| Frozen PR #117 reference | `codex/wp-rel-01` at `7bb9b5a88494027832cfe1553cc3c6c464702ab6`, inspected read-only |

The dirty primary `Pro` checkout was not used, reset, stashed, staged, or edited. Work ran in `/private/tmp/Chapterflow-IOS-wp-dev-01-bootstrap`, created directly from the verified starting revision. No backend source or contract changed.

### Implemented behavior

- `AppConfig` retains whether each required Info.plist key was absent, while preserving its existing string API.
- Validation covers `API_BASE_URL`, `COGNITO_REGION`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, and `COGNITO_DOMAIN` with typed fields and issue categories.
- Example-domain fragments, explicit template words, unexpanded build settings, and X-filled values are rejected before shape validation.
- Public API URLs require HTTPS; `localhost`, `127.0.0.1`, and `::1` remain valid HTTP development endpoints. User info, queries, and fragments are rejected.
- Cognito region, pool, client, and hostname shapes are checked, including pool-region agreement. Valid required values are trimmed before service construction.
- Invalid validation results contain ordered field/category issues only. Diagnostics add only coarse build identity, service-construction readiness, and the stable support code `CF-DEV-CFG-001`.
- `ValidatedAppConfig` is the capability required by `AppModel`; its initializer can no longer read or accept an unchecked configuration.
- `AppBootstrap` validates and conditionally creates `AppModel` once in the app initializer. SwiftUI receives the stored result and cannot recreate the graph during root-view initialization or body reevaluation.
- Invalid configuration routes to a dedicated scrollable root. Debug copy provides local setup guidance; non-Debug copy remains generic. Neither path exposes raw values or product UI.
- The existing deterministic UI harness gets a valid synthetic `.test` configuration only when both `CF_STUB_SERVER=1` and `CF_HERMETIC_TEST_CONFIGURATION=1` are explicit. Auth bypass alone and normal Debug launches cannot activate it.
- A separate Debug-only invalid fixture exists solely to test the fail-closed root; that test also enables URL stubbing so a validator regression cannot contact a live service.
- The AppFeature macOS build/test host uses an inert notification authorizer because `UNUserNotificationCenter.current()` traps in a non-application SwiftPM runner. Shipping iOS construction is unchanged.
- Existing mobile maintenance/update configuration remains behind the valid bootstrap and its package tests remain green.

No setup action was added because the root has no safe in-app action that can edit local build configuration. The screen instead gives direct, actionable file guidance.

### Changed files

Configuration and bootstrap:

- `Secrets.example.xcconfig`
- `ChapterFlow/ChapterFlowApp.swift`
- `ChapterFlow/TestSupport/CFAppLaunchSupport.swift`
- `Packages/CoreKit/Sources/CoreKit/AppConfig.swift`
- `Packages/CoreKit/Sources/CoreKit/Config/AppConfigValidation.swift`
- `Packages/CoreKit/Sources/CoreKit/Config/AppConfigurationTypes.swift`
- `Packages/CoreKit/Sources/CoreKit/Config/ConfigurationValueInspection.swift`
- `Packages/CoreKit/Sources/CoreKit/Observability/AppConfigurationDiagnostics.swift`

Application composition and UI:

- `Packages/AppFeature/Sources/AppFeature/AppModel.swift`
- `Packages/AppFeature/Sources/AppFeature/AppRootView.swift`
- `Packages/AppFeature/Sources/AppFeature/ConfiguredAppRootView.swift`
- `Packages/AppFeature/Sources/AppFeature/DebugMenuView.swift`

Tests:

- `Packages/CoreKit/Tests/CoreKitTests/AppConfigValidationTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/AppModelTestSupport.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/AppModelTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/QuickActionTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/ConfiguredAppRootViewTests.swift`
- `Packages/AppFeature/Tests/AppFeatureTests/InvalidDevelopmentConfigurationRenderTests.swift`
- `ChapterFlowUITests/ChapterFlowUITests.swift`
- `ChapterFlowUITests/Flows/SignInFlowTests.swift`

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
| Skills | `swiftui-expert-skill`, `swift-concurrency`, `swift-testing-expert`, `mobile-ios-design`, and the GitHub publish workflow |
| Specialized tooling | XcodeBuildMCP session defaults, launch, semantic snapshot, and screenshot; SwiftPM; `xcodebuild`; SwiftLint; local Git; connected GitHub tooling for publication |

No backend search was needed because WP-DEV-01 changes no endpoint, serializer, auth contract, schema, storage, or deployment behavior. No official Apple documentation lookup was required for a new platform API; current SwiftUI, Observation, concurrency, accessibility, and testing guidance from the loaded skills was applied.

### Validation evidence

All pass claims below apply to final tested implementation revision `53603a2532e8e9ec8b28536009da295b9a1fc522`. The later evidence-only documentation change does not affect compiled sources or tests.

#### Focused package tests - PASS

```sh
swift test --package-path Packages/CoreKit
```

Result: exit 0; **141 tests in 25 suites passed**. Coverage includes valid, normalized, missing, empty, malformed, unexpanded, template/example, X-filled, URL transport, region mismatch, ordering, redaction, and diagnostic-record cases.

```sh
swift test --package-path Packages/AppFeature
```

Result: exit 0; **67 tests in 18 suites passed**. Invalid bootstrap invoked the graph factory zero times; valid bootstrap invoked it exactly once; 50 repeated SwiftUI body evaluations retained one graph; diagnostics failures did not alter routing. Light, Dark, 320x568, and AX5 render guards passed.

The first AppFeature attempt compiled but its macOS test process trapped when existing AppModel tests reached Apple's process-global notification center without an application bundle. The host-only inert authorizer seam was added; the exact command then passed. This was diagnosed rather than retried blindly.

#### Exact 17-package CI loop - PASS

The unmodified package list and shared-scratch loop from `.github/workflows/pr.yml` ran with:

```sh
swift test --package-path "Packages/$pkg" --scratch-path "$PWD/.spm-build" --parallel
```

Result: **17 of 17 package targets passed**: Models, CoreKit, Networking, Fixtures, DesignSystem, AIFeature, AuthKit, EngagementFeature, LibraryFeature, NotificationsFeature, OnboardingFeature, PaywallFeature, Persistence, QuizFeature, ReaderFeature, SettingsFeature, and SocialFeature.

An initial sandboxed invocation could not compile any manifest because Swift required `~/.cache/clang/ModuleCache`; it was stopped once the common infrastructure cause was proven. The exact loop was then authorized outside that restriction and passed. The generated shared scratch was deleted afterward; no source, fixture, snapshot, or other worktree was removed.

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

#### Exact ChapterFlowUITests lane - PASS after diagnosed test-query correction

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
- `SignInFlowTests`: 8 passed, including invalid-normal and explicit-hermetic configuration paths;
- `SmokeLaneTests`: 2 intentionally skipped because `CF_REAL_API=1` was absent;
- total: **22 executed, 20 passed, 2 skipped, 0 failures**.

The first full run had one failure because the new test searched `.otherElements` while the runtime accessibility tree attached the root identifier to its `ScrollView`. XcodeBuildMCP proved the invalid screen was present. A focused rerun then exposed the same element-type assumption for the guidance container. The assertions were made identifier-based and element-type agnostic; the focused test passed, followed by the complete green lane above. No production behavior, timeout, retry policy, skip, or test scope was weakened.

#### Lint and diff - PASS

```sh
swiftlint lint --strict --reporter github-actions-logging
git diff --check
```

Results: SwiftLint exit 0 with **0 violations and 0 serious violations in 735 files**; diff check exit 0. An independent read-only reviewer reported no remaining P0-P2 findings and separately passed strict no-cache lint and diff checks.

### Runtime and accessibility evidence

- With the exact CI-style placeholder build installed, XcodeBuildMCP launched `com.chapterflow.ios` with **no test environment variables**. Visual inspection showed only `ChapterFlow Needs Setup`, four nonsecret issue summaries, local setup guidance, and support code `CF-DEV-CFG-001`; there was no login, library, paywall, or other product UI.
- A separate explicit invalid-fixture launch produced a 34-element semantic snapshot with the fail-closed root identifier and no interactive targets.
- The UI uses semantic DesignSystem colors and fonts, a flexible `ScrollView`, no fixed text/control height, heading traits, contained reading order, hidden decorative icons, and text labels in addition to icons/color.
- Render guards covered Light Mode, Dark Mode, 320x568 geometry, and AX5 Dynamic Type. The surface has no motion; the AX5 guard also disables transaction animation, satisfying Reduce Motion without adding a separate animation path.
- XCUITest verified the root, heading, guidance, support code, absence of tab UI, and absence of login controls. VoiceOver order follows source order and `.contain` accessibility grouping; no physical VoiceOver session was claimed.

### Security, privacy, contracts, and migrations

- Invalid state and diagnostics retain no raw AppConfig, URL, Cognito ID, token, DSN, credential, request/response body, or personal data.
- Tests reflect invalid results and records to confirm private URL and identifier strings are absent.
- Invalid configuration cannot reach `AppModel`, `AuthService`, `SessionManager`, `APIClient`, analytics transport, StoreKit/entitlements, live repositories, or other network-backed feature services.
- Synthetic test values use reserved `.test` hosts and fake non-production identifiers. They require explicit Debug-only launch environment activation.
- No API contract, model wire shape, persistence schema, migration, deployment order, or rollback mechanism changed. Rollback is a direct revert of the focused bootstrap commit.

### Acceptance and contamination review

| Requirement | Result |
|---|---|
| Five required values typed and validated | PASS |
| Placeholder/example configuration rejected | PASS |
| Invalid path creates zero live graphs/services | PASS |
| Valid path creates exactly one graph | PASS |
| SwiftUI reevaluation cannot duplicate graph | PASS |
| Explicit hermetic UI-test configuration only | PASS |
| Normal Debug placeholder launch remains invalid | PASS |
| Privacy-safe deterministic diagnostics | PASS |
| Invalid root accessibility/render matrix | PASS |
| Existing maintenance/update tests | PASS |
| Sign-In, Home, Library, Book Detail, purchase-fixture regressions | PASS |
| No Audio or Social file changed | PASS |
| No PR #117 commit cherry-picked wholesale | PASS |
| No release-only configuration or machinery imported | PASS |

The complete diff contains no App Store identity, product/price/subscription-group change, release manifest, export options, waiver, attestation, signing, provisioning, TestFlight detection, production Sentry requirement, deployment logic, Audio change, or Social change. Existing StoreKit behavior and its deterministic fixture tests were exercised but not modified.

### Remaining limitations and prohibited-action confirmation

- Live Cognito/SIWA, authenticated deployed-backend behavior, account switching, real StoreKit transactions, StoreKit Sandbox, physical-device installation, and production configuration were **not run** and are not claimed.
- The two optional real-API smoke tests were **skipped by design** because no `CF_REAL_API=1` authorization or token was supplied.
- No physical VoiceOver, Reduce Transparency, or signed-device session was run; the deterministic semantic and render evidence above is the scoped accessibility proof.
- No merge, deployment, App Store Connect action, TestFlight action, Sandbox purchase, signing/provisioning change, production-data action, PR #117 mutation, or unrelated-user change occurred.
