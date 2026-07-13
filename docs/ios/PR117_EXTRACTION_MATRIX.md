# PR #117 Extraction Matrix

**Status:** Development-planning evidence only. PR #117 and `codex/wp-rel-01` are frozen during extraction. No row authorizes cherry-picking, release work, deployment, or PR mutation.

## Revision evidence

- PR base and `origin/main`: `03747305819eccc8bb3c738a21e79d78a82d587d`
- PR head, local `codex/wp-rel-01`, and `origin/codex/wp-rel-01`: `7bb9b5a88494027832cfe1553cc3c6c464702ab6`
- Merge base: exactly `03747305819eccc8bb3c738a21e79d78a82d587d`
- Range: 19 linear commits
- Net diff: 125 files, 15,706 insertions, 1,492 deletions
- GitHub PR #117: open draft, unmerged, mergeable; base `main`; 19 commits; 125 files; 15,706 additions and 1,492 deletions (live connected-GitHub read on 2026-07-13).
- Release worktree: `/private/tmp/Chapterflow-IOS-wp-rel-01`, clean and unchanged
- Main checkout: dirty on `Pro`; local `main` and `Pro` are both at `7291e8c3d43b37d3e63f732ffc3a6cc9a8c832d1`. It was not changed.
- `ChapterFlow.xctestplan` was touched by intermediate commits, but its base and head blob are both `4fe54575769b813a092a1f78193941b6875653b1`; it has no net PR diff.
- GitHub metadata and the base/head SHAs were independently verified through the connected GitHub app. Labels, review threads, and workflow logs were not needed for classification and were not changed.

## All 19 commits classified

| # | Commit | Subject | Classification | Extraction disposition |
|---:|---|---|---|---|
| 1 | `94ebef7fad532c5e4d6c4b9d3bf2dfa7a1cc8b0b` | Implement WP-REL-01 release and StoreKit hardening | **reject/drop as an atomic commit**; content spans development configuration/bootstrap, StoreKit/entitlement runtime correctness, hermetic test infrastructure, release-only/deferred, and unrelated work | 120 files and 13,989 insertions. Never cherry-pick. Reconstruct approved slices by file and hunk. |
| 2 | `ce1621255ad8dea13e698400ee40761d4592ad85` | ci: isolate macOS snapshot verification | hermetic test infrastructure | Depends on the initial snapshot and release-preflight additions. |
| 3 | `f2c47be41c36da3111b46180c4e24b07ec6ed803` | test: stabilize macOS SwiftUI snapshots | hermetic test infrastructure | Depends on both snapshot-support implementations. |
| 4 | `48ca39eb8962218766adacbcd37a9f9cee3b1b71` | ci: gate release snapshots on UIKit | hermetic test infrastructure | Touches mixed CI and release-test files; do not cherry-pick alone. |
| 5 | `9888290a15f194c336809d2de21c3280c32883cb` | test: scroll hard gate actions into view | hermetic test infrastructure | Depends on configuration-gate UI and its UI-test target wiring. |
| 6 | `ab04ae2dc2f7baabd2c9e04e3c0a2068b8db531f` | fix: isolate audio notification task captures | unrelated and requiring a separate PR | Coherent AudioPlayer retention fix and regression test. |
| 7 | `6d8a43d82b038b9324c5daf1e2d90783b679cc8e` | test: configure deterministic StoreKit purchases | hermetic test infrastructure | First `SKTestSession` approach; substantially superseded by later commits. |
| 8 | `237c3310beea906ce33af1dec3d1b4a7fc88b210` | test: activate StoreKit catalog for UI tests | hermetic test infrastructure | Changes catalog identity/pricing and the general test plan; the test-plan change later nets to zero. |
| 9 | `1860ebe20b2c43022496445e0d73f4c56692071e` | ci: pin StoreKit lane to installed iOS 26.2 | hermetic test infrastructure | Ephemeral runtime pin, later superseded. |
| 10 | `53dfb1ca09cf880fa0830999e53d0c569b5b456b` | test: require tab selection before StoreKit flow | hermetic test infrastructure | Makes navigation failure explicit instead of silently continuing. |
| 11 | `16a1291149bdc4b1ab2ac88805c481c4a9f5479b` | test: wait for StoreKit plan selection | hermetic test infrastructure | Deterministic wait for selected-plan state. |
| 12 | `8b69f4f7eb860dc4da72a10510ca61f88d5fb6a1` | test: activate StoreKit before app launch | hermetic test infrastructure | Depends on catalog, scheme, project wiring, and later warm-install adjustment. |
| 13 | `f2a74fcbca941a5c2f54b0bb8ecea7338a63658a` | fix(ci): bind StoreKit catalog in isolated recovery lane | hermetic test infrastructure, with release-documentation hunks | Adds dedicated plan/scheme/lane; not independently cherry-pickable. |
| 14 | `f152a5e48e966dc00676f5b903309609db628d40` | ci: isolate StoreKit on stable simulator | hermetic test infrastructure | Environment-specific CI isolation, later revised. |
| 15 | `f527a435aedb5935aaa15e6cbf3fee5d2a2615e0` | test: bypass invalid StoreKit tab frame | hermetic test infrastructure | Uses an existing DEBUG route to avoid unrelated simulator tab hit-testing. Retest before retaining. |
| 16 | `f9a35e9a1ceb064f99c106a02b32a85435bb5b6a` | test: install app before StoreKit session | hermetic test infrastructure | Warm-installs before binding `SKTestSession`; depends on the full preceding harness. |
| 17 | `3891dc53d86fb1947d1ad4cef83c51bd9c7f635a` | ci: match StoreKit toolchain to runtime | hermetic test infrastructure | Ephemeral toolchain/runtime policy. |
| 18 | `81d584f134b91a297fe0104129e801ce5b36d5d2` | ci: fail fast without fixed StoreKit runtime | hermetic test infrastructure | Depends on the entire StoreKit CI lane and a fixed runtime assumption. |
| 19 | `7bb9b5a88494027832cfe1553cc3c6c464702ab6` | ci: add controlled StoreKit simulator waiver | **reject/drop** | Adds a skip/waiver and evidence-attestation machinery. Required evidence is absent from the commit tree and the whole slice is excluded from the development phase. |

## All 125 changed files classified

The primary classifications below are mutually exclusive and total 125 files. Mixed-file hazards are listed after the groups.

### Development configuration/bootstrap — 18 files

1. `ChapterFlow.xcodeproj/project.pbxproj`
2. `ChapterFlow/ChapterFlowApp.swift`
3. `Config/Base.xcconfig`
4. `Config/Debug.xcconfig`
5. `Config/Info.plist`
6. `Config/Staging.xcconfig`
7. `Packages/AppFeature/Sources/AppFeature/AppConfigGateView.swift`
8. `Packages/AppFeature/Sources/AppFeature/AppConfigService.swift`
9. `Packages/AppFeature/Sources/AppFeature/ConfiguredAppRootView.swift`
10. `Packages/AppFeature/Sources/AppFeature/DebugMenuView.swift`
11. `Packages/AppFeature/Sources/AppFeature/HostNotificationAuthorizer.swift`
12. `Packages/CoreKit/Sources/CoreKit/Analytics/AnalyticsEvent.swift`
13. `Packages/CoreKit/Sources/CoreKit/AppConfig.swift`
14. `Packages/CoreKit/Sources/CoreKit/Config/AppConfigValidation.swift`
15. `Packages/CoreKit/Sources/CoreKit/Config/AppConfigurationTypes.swift`
16. `Packages/CoreKit/Sources/CoreKit/Config/ConfigurationValueInspection.swift`
17. `Packages/CoreKit/Sources/CoreKit/Observability/AppConfigurationDiagnostics.swift`
18. `Secrets.example.xcconfig`

### StoreKit/entitlement runtime correctness — 35 files

1. `Packages/AppFeature/Sources/AppFeature/AppModel.swift`
2. `Packages/AppFeature/Sources/AppFeature/AppRootView.swift`
3. `Packages/PaywallFeature/Sources/PaywallFeature/ApplePurchaseVerificationResponse.swift`
4. `Packages/PaywallFeature/Sources/PaywallFeature/AsyncEventBroadcaster.swift`
5. `Packages/PaywallFeature/Sources/PaywallFeature/BillingEndpoints.swift`
6. `Packages/PaywallFeature/Sources/PaywallFeature/BillingState.swift`
7. `Packages/PaywallFeature/Sources/PaywallFeature/EntitlementAccountScope.swift`
8. `Packages/PaywallFeature/Sources/PaywallFeature/EntitlementRepository.swift`
9. `Packages/PaywallFeature/Sources/PaywallFeature/EntitlementService.swift`
10. `Packages/PaywallFeature/Sources/PaywallFeature/EntitlementServicePreview.swift`
11. `Packages/PaywallFeature/Sources/PaywallFeature/LiveEntitlementRepository.swift`
12. `Packages/PaywallFeature/Sources/PaywallFeature/PaywallComponents.swift`
13. `Packages/PaywallFeature/Sources/PaywallFeature/PaywallModel+BillingErrors.swift`
14. `Packages/PaywallFeature/Sources/PaywallFeature/PaywallModel.swift`
15. `Packages/PaywallFeature/Sources/PaywallFeature/PaywallProductsUnavailableView.swift`
16. `Packages/PaywallFeature/Sources/PaywallFeature/PaywallSuccessOverlay.swift`
17. `Packages/PaywallFeature/Sources/PaywallFeature/PaywallView+Previews.swift`
18. `Packages/PaywallFeature/Sources/PaywallFeature/PaywallView.swift`
19. `Packages/PaywallFeature/Sources/PaywallFeature/ProSourceKind.swift`
20. `Packages/PaywallFeature/Sources/PaywallFeature/ProductAvailabilityState.swift`
21. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitAccountBinding.swift`
22. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitConfig.swift`
23. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitErrorLogging.swift`
24. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitService+Offers.swift`
25. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitService+TransactionCoordination.swift`
26. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitService.swift`
27. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitServicing.swift`
28. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitTransactionProcessingCoordinator.swift`
29. `Packages/PaywallFeature/Sources/PaywallFeature/StoreKitTransactionVerification.swift`
30. `Packages/PaywallFeature/Sources/PaywallFeature/StoreProductInfo.swift`
31. `Packages/PaywallFeature/Sources/PaywallFeature/SubscriptionManagementModel.swift`
32. `Packages/PaywallFeature/Sources/PaywallFeature/SubscriptionManagementView+Previews.swift`
33. `Packages/PaywallFeature/Sources/PaywallFeature/SubscriptionManagementView.swift`
34. `Packages/PaywallFeature/Sources/PaywallFeature/TaskCancellationHandle.swift`
35. `Packages/PaywallFeature/Sources/PaywallFeature/WinBackDisplayInfo.swift`

### Hermetic test infrastructure — 58 files

1. `.github/workflows/pr.yml`
2. `.gitignore`
3. `ChapterFlow-StoreKitTest.xctestplan`
4. `ChapterFlow.xcodeproj/xcshareddata/xcschemes/ChapterFlow-StoreKitTest.xcscheme`
5. `ChapterFlow/TestSupport/CFAppLaunchSupport.swift`
6. `ChapterFlow/TestSupport/CFStubRoutes.swift`
7. `ChapterFlow/TestSupport/CFUITestSessionSeeder.swift`
8. `ChapterFlowUITests/ChapterFlowUITests.entitlements`
9. `ChapterFlowUITests/ChapterFlowUITests.swift`
10. `ChapterFlowUITests/Flows/PurchaseFlowTests.swift`
11. `ChapterFlowUITests/Flows/ReleaseConfigurationFlowTests.swift`
12. `ChapterFlowUITests/Support/AppRobot.swift`
13. `Config/ChapterFlow.storekit`
14. `Packages/AppFeature/Package.swift`
15. `Packages/AppFeature/Tests/AppFeatureTests/AppConfigGateRenderGuardTests.swift`
16. `Packages/AppFeature/Tests/AppFeatureTests/AppConfigServiceTests.swift`
17. `Packages/AppFeature/Tests/AppFeatureTests/ConfiguredAppRootViewTests.swift`
18. `Packages/AppFeature/Tests/AppFeatureTests/ReferenceSnapshotSupport.swift`
19. `Packages/AppFeature/Tests/AppFeatureTests/ReleaseVisualSnapshotTests.swift`
20. `Packages/AppFeature/Tests/AppFeatureTests/__Snapshots__/hard-update-bottom-small-phone-ax5-ios.png`
21. `Packages/AppFeature/Tests/AppFeatureTests/__Snapshots__/hard-update-small-phone-ax5-ios.png`
22. `Packages/AppFeature/Tests/AppFeatureTests/__Snapshots__/hard-update-small-phone-ax5-macos.png`
23. `Packages/AppFeature/Tests/AppFeatureTests/__Snapshots__/invalid-bootstrap-bottom-small-phone-ax5-ios.png`
24. `Packages/AppFeature/Tests/AppFeatureTests/__Snapshots__/invalid-bootstrap-small-phone-ax5-ios.png`
25. `Packages/AppFeature/Tests/AppFeatureTests/__Snapshots__/invalid-bootstrap-small-phone-ax5-macos.png`
26. `Packages/AuthKit/Sources/AuthKit/AuthService.swift`
27. `Packages/AuthKit/Sources/AuthKit/SessionManager.swift`
28. `Packages/CoreKit/Tests/CoreKitTests/AppConfigValidationTests.swift`
29. `Packages/CoreKit/Tests/CoreKitTests/AppConfigurationDiagnosticsTests.swift`
30. `Packages/PaywallFeature/Package.swift`
31. `Packages/PaywallFeature/Tests/PaywallFeatureTests/AsyncEventBroadcasterTests.swift`
32. `Packages/PaywallFeature/Tests/PaywallFeatureTests/EntitlementServiceIsolationTests.swift`
33. `Packages/PaywallFeature/Tests/PaywallFeatureTests/EntitlementServiceTests.swift`
34. `Packages/PaywallFeature/Tests/PaywallFeatureTests/Fixtures/apple_verify_success.json`
35. `Packages/PaywallFeature/Tests/PaywallFeatureTests/OfferSurfaceTests.swift`
36. `Packages/PaywallFeature/Tests/PaywallFeatureTests/PaywallAccessibilityTests.swift`
37. `Packages/PaywallFeature/Tests/PaywallFeatureTests/PaywallConcurrencySafetyTests.swift`
38. `Packages/PaywallFeature/Tests/PaywallFeatureTests/PaywallFeatureTests.swift`
39. `Packages/PaywallFeature/Tests/PaywallFeatureTests/PaywallNetworkAndRestoreTests.swift`
40. `Packages/PaywallFeature/Tests/PaywallFeatureTests/PaywallRenderGuardTests.swift`
41. `Packages/PaywallFeature/Tests/PaywallFeatureTests/PaywallSafetyTests.swift`
42. `Packages/PaywallFeature/Tests/PaywallFeatureTests/PaywallTestHelpers.swift`
43. `Packages/PaywallFeature/Tests/PaywallFeatureTests/ReferenceSnapshotSupport.swift`
44. `Packages/PaywallFeature/Tests/PaywallFeatureTests/ReleaseVisualSnapshotTests.swift`
45. `Packages/PaywallFeature/Tests/PaywallFeatureTests/StoreKitAccountBindingTests.swift`
46. `Packages/PaywallFeature/Tests/PaywallFeatureTests/StoreKitAuthoritativeProcessingTests.swift`
47. `Packages/PaywallFeature/Tests/PaywallFeatureTests/StoreKitCoalescingTests.swift`
48. `Packages/PaywallFeature/Tests/PaywallFeatureTests/StoreKitConfigurationTests.swift`
49. `Packages/PaywallFeature/Tests/PaywallFeatureTests/StoreKitResidualTransactionTests.swift`
50. `Packages/PaywallFeature/Tests/PaywallFeatureTests/StoreKitServiceTests.swift`
51. `Packages/PaywallFeature/Tests/PaywallFeatureTests/SubscriptionManagementTests.swift`
52. `Packages/PaywallFeature/Tests/PaywallFeatureTests/__Snapshots__/fail-closed-products-bottom-small-phone-ax5-ios.png`
53. `Packages/PaywallFeature/Tests/PaywallFeatureTests/__Snapshots__/fail-closed-products-small-phone-ax5-ios.png`
54. `Packages/PaywallFeature/Tests/PaywallFeatureTests/__Snapshots__/fail-closed-products-small-phone-ax5-macos.png`
55. `Packages/PaywallFeature/Tests/PaywallFeatureTests/__Snapshots__/success-reduced-motion-bottom-small-phone-ax5-ios.png`
56. `Packages/PaywallFeature/Tests/PaywallFeatureTests/__Snapshots__/success-reduced-motion-small-phone-ax5-ios.png`
57. `Packages/PaywallFeature/Tests/PaywallFeatureTests/__Snapshots__/success-reduced-motion-small-phone-ax5-macos.png`
58. `scripts/tests/test-storekit-catalog.py`

### Release-only/deferred — 9 files

1. `.github/workflows/release.yml`
2. `Config/ApprovedReleaseIdentity.json`
3. `Config/ExportOptions.plist`
4. `Config/Release.xcconfig`
5. `Config/ReleaseManifest.schema.json`
6. `Config/ReleaseManifest.template.json`
7. `docs/ios/SIGNING-AND-RELEASE.md`
8. `scripts/release-config/release_config.py`
9. `scripts/tests/test-release-config.sh`

### Unrelated and requiring a separate PR — 4 files

1. `Packages/AIFeature/Sources/AIFeature/Audio/AudioPlayer.swift`
2. `Packages/AIFeature/Tests/AIFeatureTests/AudioExpiryRecoveryTests.swift`
3. `Packages/SocialFeature/Sources/SocialFeature/Repository/FakeSocialRepository.swift`
4. `Packages/SocialFeature/Sources/SocialFeature/Views/Reflections/ReflectionRowView.swift`

### Reject/drop — 1 complete file, plus hunks in mixed files

1. `Config/StoreKitSimulatorWaiver.json`

Also reject the waiver/attestation hunks added by `7bb9b5a…` in:

- `.github/workflows/pr.yml`
- `docs/ios/SIGNING-AND-RELEASE.md`
- `scripts/tests/test-storekit-catalog.py`

The waiver and workflow require these paths, which are absent from the `7bb9b5a…` tree:

- `docs/ios/release-evidence/storekit/pr-117/attestation.v1.json`
- `docs/ios/release-evidence/storekit/pr-117/catalog.png`
- `docs/ios/release-evidence/storekit/pr-117/backend-unavailable.png`
- `docs/ios/release-evidence/storekit/pr-117/sandbox-purchase-history.png`
- `docs/ios/release-evidence/storekit/pr-117/restore-success.png`
- `docs/ios/release-evidence/storekit/pr-117/relaunch-pro.png`

## Mixed-file cautions

- `ChapterFlow.xcodeproj/project.pbxproj` includes development configuration, Release configuration, StoreKit catalog resource wiring, the dedicated StoreKit scheme/test target, release-configuration UI tests, and UI-test entitlements. Hand-patch it per extraction PR.
- `.github/workflows/pr.yml` combines ordinary build/test changes, deterministic snapshot work, release-preflight tests, StoreKit recovery lanes, label-driven scope logic, and the rejected waiver. Never copy it wholesale.
- `.gitignore` combines general SPM test artifacts and Python release-tool artifacts. Carry only lines required by the destination PR.
- `Config/Base.xcconfig`, `Config/Info.plist`, `Secrets.example.xcconfig`, `AppConfig.swift`, `AppConfigValidation.swift`, and `AppConfigurationDiagnostics.swift` combine reusable development bootstrap with release provenance, App Store identity, StoreKit product policy, Sentry production policy, and TestFlight-only diagnostics.
- `AppConfigGateView.swift` combines reusable accessibility/fail-closed behavior with product-specific App Store update behavior.
- `AppModel.swift` and `AppRootView.swift` combine configuration diagnostics, TestFlight detection, service construction, entitlement account activation/deactivation, auth lifecycle, and sign-out cleanup.
- `CFAppLaunchSupport.swift`, `CFStubRoutes.swift`, `PurchaseFlowTests.swift`, and `Config/ChapterFlow.storekit` contain purported product identifiers/prices. Do not treat those as authorized product decisions.
- `scripts/tests/test-storekit-catalog.py` includes useful structural checking plus 922 lines of rejected waiver/attestation machinery from the final commit.
- The AuthKit source changes are DEBUG-only fixture-identity updates required because StoreKit account binding expects a UUID subject; they are not production-auth changes.

## Dependencies and cherry-pick hazards

1. **The initial commit is indivisible in git but not in product scope.** It contains almost the entire PR and every substantive class. It is unsafe to cherry-pick even if subsequent commits appear small.

2. **Bootstrap is a chain:** `xcconfig/project/Info.plist → AppConfig parsing → validation/types → ChapterFlowApp → ConfiguredAppRootView → AppModel/AppRootView`. Extracting only one layer either fails compilation or changes launch behavior without its tests.

3. **Bootstrap is contaminated with release policy.** Production provenance, exact App Store identity, StoreKit products, Sentry requirements, and TestFlight diagnostics share source files with API/Cognito development validation. A development PR must hand-extract only development environment parsing, required API/auth validation, pre-service fail-closed routing, and privacy-safe development diagnostics.

4. **Account isolation crosses packages:** `Auth session subject → AppModel.handleSignedIn/handleSignedOut → EntitlementAccountScope → EntitlementService account activation and cache key → StoreKitAccountBinding → StoreKitService activation/deactivation`. The UUID fixture changes, second-account tests, and sign-out clearing belong with this slice.

5. **StoreKit transaction correctness is a coupled set:** `StoreKitServicing + StoreKitAccountContext + transaction-processing coordinator + broadcaster + cancellation handle + verification response + repository endpoint + StoreKitService + tests`. Individual files are not safe cherry-pick units.

6. **Backend contract is a hard prerequisite and is source-verified.** Backend main `968ff67ecafbed7e8e1d4c7b77badf507cfc5aee` implements `POST /book/me/billing/apple/verify` and returns the raw `ok`, `processed`, `transactionState`, and authoritative entitlement body decoded by PR #117. The iOS optionality is conservative and fail-closed. Live deployment identity/configuration remains unverified, so extraction may rely on this source contract and hermetic fixtures but may not claim deployed purchase success.

7. **Diagnostics couple CoreKit and PaywallFeature.** `StoreKitService` depends on `StoreKitDiagnosticsRecording`, currently declared with release/TestFlight diagnostic types. Either extract a minimal neutral protocol or defer diagnostic injection.

8. **Paywall UI follows the runtime layer.** `PaywallModel`, subscription management, availability states, offers, success overlays, and views depend on the new service protocol and value types. Offers/win-back behavior should be a deliberate later slice.

9. **The StoreKit UI harness is one unit:** dedicated scheme/test plan, project resource wiring, catalog, UI-test app-group entitlement, restore-signal file, mutable stub state, UUID fixture identity, purchase flow, and CI lane. It also depends on unverified product/pricing values and unstable simulator/toolchain workarounds.

10. **Intermediate StoreKit commits supersede each other.** `6d8a43d`, `237c331`, `8b69f4f`, `f2a74fc`, and `f9a35e9` represent successive setup strategies. Cherry-picking any one produces an incomplete or obsolete harness.

11. **CI runtime pins are ephemeral.** `1860ebe`, `f152a5e`, `3891dc5`, and `81d584f` encode specific hosted-image and Xcode/runtime assumptions. Re-derive them from current CI instead of replaying them.

12. **Snapshot PNGs are not standalone evidence.** They depend on the exact source views, snapshot support, package resource declarations, UIKit gating, Dynamic Type, Reduce Motion, and platform rendering. Extract tests and baselines together after verifying them anew.

13. **Final waiver is unusable for this phase.** The final commit permits a StoreKit test disposition based on external/missing evidence and is expressly outside the development-phase authorization. Drop the commit and all of its hunks.

## Recommended extraction order

1. **WP-DEV-01 — deterministic development bootstrap:** API/Cognito/environment configuration, pre-service validation, explicit invalid-configuration route, and focused CoreKit/AppFeature tests. Exclude Release/Staging deployment policy, manifests, signing, App Store identity, StoreKit product requirements, Sentry production rules, TestFlight detection, and release snapshots.
2. **WP-DEV-02 — account-scoped entitlement isolation:** per-account cache, activation/deactivation, immediate sign-out clearing, and second-account isolation with hermetic tests.
3. **WP-DEV-03 — StoreKit transaction coordination:** protocols, task lifecycle, coalescing, account binding, authoritative processing, and residual transactions. Block until backend contract verification.
4. **WP-DEV-04 — paywall availability/billing state:** safe product failures, source-safe subscription management, accessibility, and rendering tests. Treat offers/win-back as an explicit sub-slice.
5. **WP-DEV-05 — hermetic StoreKit integration harness:** dedicated scheme/test plan and purchase/relaunch/restore test, only after product configuration is authoritatively supplied and the test executes without a waiver.
6. **Final release phase:** all WP-REL work, including Release xcconfig, identity manifest, archive/export, signing, App Store Connect, TestFlight, Sandbox attestation/evidence, deployment, and release labeling.

The safest first implementation PR after WP-DEV-00 is **WP-DEV-01 deterministic development bootstrap** because it is foundational, avoids backend/product decisions, and can be verified independently before entitlement extraction.

## Blockers and uncertainties

- Current GitHub metadata and both repositories' main SHAs were verified through the connected GitHub app. Workflow logs, labels, comments, and review-thread state were not needed for classification and were not changed.
- Backend main `968ff67ecafbed7e8e1d4c7b77badf507cfc5aee` source matches the iOS verification decoder and endpoint. No live endpoint was called, so deployed revision and environment-owned Apple configuration remain unverified.
- Product IDs, prices, Apple app ID, team ID, and subscription group in PR117 are not treated as newly authorized product configuration.
- The fixed Xcode/iOS 26.6 StoreKit assumptions were not run and are time-sensitive.
- Classification did not depend on PR #117 builds or tests. Current-main baseline commands and runtime evidence are recorded separately in `DEVELOPMENT_EXECUTION_STATUS.md`.

## Mutation confirmation

No file, commit, ref, worktree state, or GitHub metadata belonging to PR #117 or `codex/wp-rel-01` was changed. This matrix is published only as part of the documentation-only WP-DEV-00 control-plane PR. No deployment, TestFlight, StoreKit Sandbox, App Store Connect, release-label, merge, close, comment, or push action occurred against PR #117.
