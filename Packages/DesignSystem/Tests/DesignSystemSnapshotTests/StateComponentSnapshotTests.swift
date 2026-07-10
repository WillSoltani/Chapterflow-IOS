/// Render-guard coverage for the loading / empty / error / offline feedback
/// components that aren't part of the pixel-compared `DesignSystemGallery`.
///
/// These components lean on system materials (`.regularMaterial`,
/// `.glassEffect`, `ContentUnavailableView`) whose exact pixels vary across OS
/// point releases, so committing reference images would flake in CI. Instead we
/// render them off-screen across the light / dark / large-Dynamic-Type matrix
/// and assert a non-empty bitmap is produced — catching layout traps and
/// crashes without a drift-prone reference. The solid-token components stay
/// pixel-snapshotted in ``DesignSystemSnapshotTests``.

import Testing
import SwiftUI
@testable import DesignSystem

@MainActor
@Suite("DesignSystem State Components")
struct StateComponentSnapshotTests {

    /// Renders `view` off-screen and asserts a bitmap is produced.
    @MainActor
    private func assertRenders(
        _ view: some View,
        _ label: Comment,
        size: CGSize = CGSize(width: 393, height: 600)
    ) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
#if canImport(AppKit)
        #expect(renderer.nsImage != nil, label)
#else
        #expect(renderer.uiImage != nil, label)
#endif
    }

    /// A panel bundling every feedback / state component for one render pass.
    private var statesPanel: some View {
        VStack(spacing: .cfSpacing20) {
            OfflineBannerView(isOffline: true, pendingCount: 3)
            CacheMissView(title: "Chapter not available offline", onDownload: {})
                .frame(height: 200)
            CFEmptyState(
                systemImage: "tray",
                title: "Nothing to review",
                description: "You're all caught up. New cards appear as you read.",
                actionLabel: "Browse Library"
            ) {}
            .frame(height: 220)
            CFToast("Reading progress saved", systemImage: "checkmark.circle.fill")
        }
        .padding(.cfSpacing20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfGroupedBackground)
    }

    @Test("Feedback / state components render in light mode")
    func statesLight() {
        assertRenders(statesPanel.environment(\.colorScheme, .light), "states — light")
    }

    @Test("Feedback / state components render in dark mode")
    func statesDark() {
        assertRenders(statesPanel.environment(\.colorScheme, .dark), "states — dark")
    }

    @Test("Feedback / state components render at accessibility5 Dynamic Type")
    func statesLargeType() {
        assertRenders(
            statesPanel.environment(\.dynamicTypeSize, .accessibility5),
            "states — AX5",
            size: CGSize(width: 393, height: 1400)
        )
    }

    @Test("CFConfetti renders without crashing (active + inactive)")
    func confettiRenders() {
        assertRenders(
            CFConfetti(isActive: true).frame(width: 320, height: 320),
            "confetti — active",
            size: CGSize(width: 320, height: 320)
        )
        assertRenders(
            CFConfetti(isActive: false).frame(width: 320, height: 320),
            "confetti — inactive",
            size: CGSize(width: 320, height: 320)
        )
    }
}
