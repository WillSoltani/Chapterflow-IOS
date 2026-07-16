import SwiftUI
import Testing
@testable import DesignSystem

@MainActor
@Suite("Editorial Foundation Snapshots")
struct EditorialFoundationSnapshotTests {
    private let compactWidth: CGFloat = 320

    @Test("editorial foundation has a stable normal reference")
    func normalReference() throws {
        let size = CGSize(width: compactWidth, height: 1_000)
        let view = foundationPanel(surfaceStyle: ReferenceSurface.light)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)

        try assertSnapshot(
            view,
            named: "editorial-foundation-normal",
            size: size
        )
    }

    @Test("editorial foundation has a stable AX5 dark reference")
    func accessibility5Reference() throws {
        let size = CGSize(width: compactWidth, height: 1_200)
        let view = foundationPanel(surfaceStyle: ReferenceSurface.dark)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .accessibility5)

        try assertSnapshot(
            view,
            named: "editorial-foundation-ax5",
            size: size
        )
    }

    @Test("editorial foundation renders RTL at the smallest supported width")
    func rightToLeftCompactRender() {
        let size = CGSize(width: compactWidth, height: 1_550)
        let view = foundationPanel(surfaceStyle: Color.cfSecondaryBackground)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.dynamicTypeSize, .large)

        assertRenders(view, label: "editorial foundation — compact RTL", size: size)
    }

    private func foundationPanel(
        surfaceStyle: some ShapeStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing20) {
            typographySpecimens

            CFEditorialSectionHeader(
                title: "Ideas worth returning to this week",
                subtitle: "A long subtitle must wrap while the action remains reachable.",
                actionTitle: "Review"
            ) {}

            CFInlineStateView(
                state: CFInlineState(
                    kind: .loading,
                    title: "Loading your highlights",
                    message: "This should only take a moment."
                ),
                snapshotSurfaceStyle: surfaceStyle
            )

            CFInlineStateView(
                state: CFInlineState(
                    kind: .empty,
                    title: "No highlights yet",
                    message: "Select a passage while reading to keep it here."
                ),
                snapshotSurfaceStyle: surfaceStyle
            )

            CFInlineStateView(
                state: CFInlineState(
                    kind: .error,
                    title: "Highlights could not load",
                    message: "Your saved highlights are still safe."
                ),
                retryAction: CFInlineRetryAction("Try Again") {},
                snapshotSurfaceStyle: surfaceStyle
            )

            CFInlineStateView(
                state: CFInlineState(
                    kind: .offline,
                    title: "You're offline",
                    message: "Reconnect to refresh this section."
                ),
                snapshotSurfaceStyle: surfaceStyle
            )
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cfGroupedBackground)
    }

    /// Stable sRGB calibration values for raster fixtures only. Production
    /// views continue to use the adaptive `cfSecondaryBackground` token.
    private enum ReferenceSurface {
        static let light = Color(
            .sRGB,
            red: 0.92,
            green: 0.92,
            blue: 0.92,
            opacity: 1
        )
        static let dark = Color(
            .sRGB,
            red: 0.16,
            green: 0.16,
            blue: 0.16,
            opacity: 1
        )
    }

    private var typographySpecimens: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            ForEach(CFEditorialTextRole.allCases, id: \.self) { role in
                VStack(alignment: .leading, spacing: .cfSpacing2) {
                    Text(role.rawValue)
                        .font(.cfEditorialCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                    Text("A thoughtful idea, clearly expressed")
                        .cfEditorialTextStyle(role)
                        .foregroundStyle(Color.cfLabel)
                }
            }
        }
    }

    private func assertRenders(
        _ view: some View,
        label: Comment,
        size: CGSize
    ) {
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
#if canImport(AppKit)
        #expect(renderer.nsImage != nil, label)
#else
        #expect(renderer.uiImage != nil, label)
#endif
    }
}
