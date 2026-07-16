import SwiftUI
import Testing
@testable import DesignSystem

#if canImport(AppKit)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

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

#if canImport(AppKit)
    @Test("snapshot comparison normalizes embedded color spaces")
    func canonicalColorSpaceComparison() throws {
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let sRGBColor = try #require(CGColor(
            colorSpace: sRGB,
            components: [0.31, 0.52, 0.73, 1]
        ))
        let displayP3Color = try #require(sRGBColor.converted(
            to: displayP3,
            intent: .relativeColorimetric,
            options: nil
        ))

        let sRGBPNG = try flatPNG(color: sRGBColor, colorSpace: sRGB)
        let displayP3PNG = try flatPNG(color: displayP3Color, colorSpace: displayP3)

        #expect(sRGBPNG != displayP3PNG)
        #expect(pixelMismatch(new: displayP3PNG, ref: sRGBPNG) == 0)
    }

    @Test("snapshot comparison rejects a materially different image")
    func materiallyDifferentComparison() throws {
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let referenceColor = try #require(CGColor(
            colorSpace: sRGB,
            components: [0.08, 0.12, 0.18, 1]
        ))
        let changedColor = try #require(CGColor(
            colorSpace: sRGB,
            components: [0.82, 0.68, 0.22, 1]
        ))

        let referencePNG = try flatPNG(color: referenceColor, colorSpace: sRGB)
        let changedPNG = try flatPNG(color: changedColor, colorSpace: sRGB)

        #expect(pixelMismatch(new: changedPNG, ref: referencePNG) == 1)
    }
#endif

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

#if canImport(AppKit)
    private func flatPNG(color: CGColor, colorSpace: CGColorSpace) throws -> Data {
        let size = 8
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        context.setBlendMode(.copy)
        context.setRenderingIntent(.relativeColorimetric)
        context.interpolationQuality = .none
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
#endif
}
