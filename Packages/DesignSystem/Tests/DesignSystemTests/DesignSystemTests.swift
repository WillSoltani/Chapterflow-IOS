import Testing
import SwiftUI
@testable import DesignSystem

@Suite("DesignSystem")
struct DesignSystemTests {

    @Test("module exposes its name")
    func moduleName() {
        #expect(DesignSystem.moduleName == "DesignSystem")
    }

    // MARK: - Color tokens

    @Test("color tokens resolve without crashing")
    func colorTokensExist() {
        let tokens: [Color] = [
            .cfAccent,
            .cfLabel,
            .cfSecondaryLabel,
            .cfTertiaryLabel,
            .cfBackground,
            .cfSecondaryBackground,
            .cfGroupedBackground,
            .cfFill,
            .cfSeparator,
        ]
        #expect(tokens.count == 9)
    }

    // MARK: - Font tokens

    @Test("font tokens resolve without crashing")
    func fontTokensResolve() {
        _ = Font.cfLargeTitle
        _ = Font.cfTitle1
        _ = Font.cfTitle2
        _ = Font.cfTitle3
        _ = Font.cfHeadline
        _ = Font.cfSubheadline
        _ = Font.cfBody
        _ = Font.cfCallout
        _ = Font.cfFootnote
        _ = Font.cfCaption
        _ = Font.cfCaption2
    }

    // MARK: - Spacing tokens

    @Test("spacing tokens are positive and strictly increasing")
    func spacingTokensOrdered() {
        let spacings: [CGFloat] = [
            .cfSpacing2,
            .cfSpacing4,
            .cfSpacing8,
            .cfSpacing12,
            .cfSpacing16,
            .cfSpacing20,
            .cfSpacing24,
            .cfSpacing32,
            .cfSpacing40,
            .cfSpacing48,
            .cfSpacing64,
        ]
        for s in spacings { #expect(s > 0) }
        for i in spacings.indices.dropFirst() {
            #expect(spacings[i] > spacings[i - 1])
        }
    }

    @Test("corner radius tokens are positive and strictly increasing")
    func cornerRadiusTokensOrdered() {
        let radii: [CGFloat] = [
            .cfRadius4,
            .cfRadius8,
            .cfRadius12,
            .cfRadius16,
            .cfRadius20,
            .cfRadius24,
        ]
        for r in radii { #expect(r > 0) }
        for i in radii.indices.dropFirst() {
            #expect(radii[i] > radii[i - 1])
        }
    }

    // MARK: - CFProgressRing clamping

    @Test("CFProgressRing clamps negative progress to 0")
    func progressRingClampsBelow() {
        _ = CFProgressRing(progress: -0.5)
        _ = CFProgressRing(progress: 0)
    }

    @Test("CFProgressRing clamps progress above 1 to 1")
    func progressRingClampsAbove() {
        _ = CFProgressRing(progress: 1.5)
        _ = CFProgressRing(progress: 1)
    }
}
