import SwiftUI
import Testing
@testable import AppFeature

@MainActor
@Suite("App configuration gate — render guards")
struct AppConfigGateRenderGuardTests {
    private let appStoreURL = URL(string: "https://apps.apple.com/app/id1234567890")
        ?? URL(fileURLWithPath: "/")

    @Test("hard update gate renders on a small phone at AX5")
    func hardGateRendersAtAX5() {
        assertRenders(
            AppUpdateRequiredView(
                message: "Update ChapterFlow to continue reading your saved books.",
                appStoreURL: appStoreURL,
                supportURL: nil
            )
            .environment(\.dynamicTypeSize, .accessibility5)
        )
    }

    @Test("maintenance gate renders on a small phone at AX5")
    func maintenanceRendersAtAX5() {
        assertRenders(
            MaintenanceView(
                message: "ChapterFlow is temporarily unavailable while we make improvements."
            )
            .environment(\.dynamicTypeSize, .accessibility5)
        )
    }

    @Test("soft update notice renders on a small phone at AX5")
    func softNudgeRendersAtAX5() {
        assertRenders(
            UpdateAvailableNudge(
                message: "A new version of ChapterFlow is ready.",
                appStoreURL: appStoreURL,
                onDismiss: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
        )
    }

    private func assertRenders(_ view: some View) {
        let size = CGSize(width: 320, height: 568)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        #if canImport(AppKit)
        #expect(renderer.nsImage != nil)
        #else
        #expect(renderer.uiImage != nil)
        #endif
    }
}
