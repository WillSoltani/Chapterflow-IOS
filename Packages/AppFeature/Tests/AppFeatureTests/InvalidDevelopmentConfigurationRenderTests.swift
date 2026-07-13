import CoreKit
import SwiftUI
import Testing
@testable import AppFeature

@MainActor
@Suite("Invalid development configuration UI")
struct InvalidConfigRenderTests {
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
