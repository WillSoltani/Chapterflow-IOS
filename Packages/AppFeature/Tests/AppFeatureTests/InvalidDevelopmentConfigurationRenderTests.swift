import CoreKit
import Foundation
import SwiftUI
import Testing
@testable import AppFeature

@MainActor
@Suite("Invalid development configuration UI")
struct InvalidConfigRenderTests {
    @Test("bootstrap preparing surface renders on the smallest phone")
    func bootstrapPreparing() {
        assertRenders(BootstrapPreparingView())
    }

    @Test("protected-data waiting renders at AX5 without a recovery action")
    func protectedDataWaitingAX5() {
        assertRenders(
            ProtectedDataWaitingView(
                supportCode: AppBootstrapStorageSupportCode
                    .protectedDataUnavailable.rawValue
            )
                .preferredColorScheme(.dark)
                .environment(\.dynamicTypeSize, .accessibility5)
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
        )
    }

    @Test("storage recovery renders in light appearance")
    func storageRecoveryLight() {
        assertRenders(
            BootstrapFailureView(
                kind: .storage,
                supportCode: AppBootstrapStorageSupportCode
                    .persistentStoreOpenOrMigration.rawValue,
                onRetry: {}
            )
        )
    }

    @Test("session recovery renders in dark appearance")
    func sessionRecoveryDark() {
        assertRenders(
            BootstrapFailureView(
                kind: .session,
                supportCode: AppBootstrapSessionFailure.supportCode,
                onRetry: {}
            )
            .preferredColorScheme(.dark)
        )
    }

    @Test("account-scope recovery renders in light appearance")
    func accountScopeRecoveryLight() {
        assertRenders(SessionScopeRecoveryView(onRetry: {}, onSignOut: {}))
    }

    @Test("account-scope recovery renders in dark appearance")
    func accountScopeRecoveryDark() {
        assertRenders(
            SessionScopeRecoveryView(onRetry: {}, onSignOut: {})
                .preferredColorScheme(.dark)
        )
    }

    @Test("account-scope recovery renders at AX5 with motion disabled")
    func accountScopeRecoveryAX5() {
        assertRenders(
            SessionScopeRecoveryView(onRetry: {}, onSignOut: {})
                .environment(\.dynamicTypeSize, .accessibility5)
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
        )
    }

    @Test("account-scope recovery copy is generic and actions follow VoiceOver order")
    func accountScopeRecoverySemantics() {
        let copy = SessionScopeRecoveryContent.heading + " " + SessionScopeRecoveryContent.message
        #expect(SessionScopeRecoveryContent.orderedActions == ["Try Again", "Sign Out"])
        #expect(!copy.localizedCaseInsensitiveContains("subject"))
        #expect(!copy.localizedCaseInsensitiveContains("account id"))
        #expect(!copy.localizedCaseInsensitiveContains("/Users/"))
        #expect(!copy.localizedCaseInsensitiveContains("error:"))
    }

    @Test("session transition copy distinguishes preparation, switching, and sign-out")
    func sessionTransitionSemantics() {
        #expect(SessionTransitionKind.preparing.visibleLabel == "Preparing your library…")
        #expect(SessionTransitionKind.switchingAccounts.visibleLabel == "Switching accounts…")
        #expect(SessionTransitionKind.signingOut.visibleLabel == "Signing you out…")
        #expect(SessionTransitionKind.signingOut.accessibilityLabel == "Signing you out")
    }

    @Test("sign-out failure is actionable and privacy safe")
    func signOutFailureSemantics() {
        let copy = SignOutFailureContent.heading + " " + SignOutFailureContent.message
        #expect(SignOutFailureContent.orderedActions == ["Try Again", "Stay Signed In"])
        #expect(!copy.localizedCaseInsensitiveContains("subject"))
        #expect(!copy.localizedCaseInsensitiveContains("account id"))
        #expect(!copy.localizedCaseInsensitiveContains("/Users/"))
        #expect(!copy.localizedCaseInsensitiveContains("error:"))
    }

    @Test("storage recovery renders at AX5 with motion disabled")
    func storageRecoveryAX5() {
        assertRenders(
            BootstrapFailureView(
                kind: .storage,
                supportCode: AppBootstrapStorageSupportCode.requiredFileStore.rawValue,
                onRetry: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        )
    }

    @Test("renders in light appearance on the smallest supported phone geometry")
    func lightSmallPhone() {
        assertRenders(InvalidDevelopmentConfigurationView(diagnostic: diagnostic))
    }

    @Test("renders in dark appearance")
    func darkAppearance() {
        assertRenders(
            InvalidDevelopmentConfigurationView(diagnostic: diagnostic)
                .preferredColorScheme(.dark)
        )
    }

    @Test("renders at AX5 in an animation-free transaction")
    func ax5ReducedMotion() {
        assertRenders(
            InvalidDevelopmentConfigurationView(diagnostic: diagnostic)
                .environment(\.dynamicTypeSize, .accessibility5)
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
        )
    }

    @Test("safe issue copy identifies fields and categories without values")
    func safeIssueCopy() {
        let reflected = String(reflecting: diagnostic)

        #expect(diagnostic.issues.map(\.code) == [
            "configuration.api_base_url.template_value",
            "configuration.cognito_user_pool_id.placeholder",
        ])
        #expect(!reflected.contains("api.chapterflow.example.com"))
        #expect(!reflected.contains("XXXXXXXXX"))
    }

    private var diagnostic: AppConfigurationDiagnosticRecord {
        AppConfigurationDiagnosticRecord(
            status: .invalid,
            buildConfiguration: .debug,
            issues: [
                AppConfigurationIssue(field: .apiBaseURL, category: .templateValue),
                AppConfigurationIssue(field: .cognitoUserPoolID, category: .placeholder),
            ],
            liveServicesConstructed: false
        )
    }

    private func assertRenders(_ view: some View) {
        let size = CGSize(width: 320, height: 568)
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height)
        )
        renderer.scale = 2

        #if canImport(AppKit)
        #expect(renderer.nsImage?.size == size)
        #else
        #expect(renderer.uiImage?.size == size)
        #endif
    }
}
