#if canImport(UIKit)
import CoreKit
import SwiftUI
import Testing
@testable import AppFeature

@MainActor
@Suite("WP-REL-01 app release snapshots", .serialized)
struct ReleaseVisualSnapshotTests {
    private let smallPhone = CGSize(width: 320, height: 568)
    private let appStoreURL = URL(string: "https://apps.apple.com/app/id1234567890")
        ?? URL(fileURLWithPath: "/")

    @Test("hard update gate remains usable at AX5 on a small phone")
    func hardUpdateGate() throws {
        let view = AppUpdateRequiredView(
            message: "Update ChapterFlow to continue reading your saved books.",
            appStoreURL: appStoreURL,
            supportURL: URL(string: "https://chapterflow.ca/support")
        )
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.locale, Locale(identifier: "en_US"))

        try assertReferenceSnapshot(
            view,
            named: "hard-update-small-phone-ax5",
            size: smallPhone
        )
    }

#if canImport(UIKit)
    @Test("hard update actions remain reachable at AX5")
    func hardUpdateGateBottom() throws {
        let view = AppUpdateRequiredView(
            message: "Update ChapterFlow to continue reading your saved books.",
            appStoreURL: appStoreURL,
            supportURL: URL(string: "https://chapterflow.ca/support")
        )
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.locale, Locale(identifier: "en_US"))

        try assertReferenceSnapshot(
            view,
            named: "hard-update-bottom-small-phone-ax5",
            size: smallPhone,
            scrollPosition: .bottom
        )
    }
#endif

    @Test("invalid production bootstrap remains usable at AX5 on a small phone")
    func invalidBootstrap() throws {
        let config = AppConfig(
            apiBaseURL: "https://api.chapterflow.ca",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_example",
            cognitoClientID: "example",
            environment: .production,
            supportURL: "https://chapterflow.ca/support"
        )
        let view = ConfiguredAppRootView(state: .invalid(
            config: config,
            issues: [ConfigurationIssue(field: .appStoreID, reason: .missing)]
        ))
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.locale, Locale(identifier: "en_US"))

        try assertReferenceSnapshot(
            view,
            named: "invalid-bootstrap-small-phone-ax5",
            size: smallPhone
        )
    }

#if canImport(UIKit)
    @Test("invalid production bootstrap support details remain reachable at AX5")
    func invalidBootstrapBottom() throws {
        let config = AppConfig(
            apiBaseURL: "https://api.chapterflow.ca",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_example",
            cognitoClientID: "example",
            environment: .production,
            supportURL: "https://chapterflow.ca/support"
        )
        let view = ConfiguredAppRootView(state: .invalid(
            config: config,
            issues: [ConfigurationIssue(field: .appStoreID, reason: .missing)]
        ))
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.locale, Locale(identifier: "en_US"))

        try assertReferenceSnapshot(
            view,
            named: "invalid-bootstrap-bottom-small-phone-ax5",
            size: smallPhone,
            scrollPosition: .bottom
        )
    }
#endif
}
#endif
