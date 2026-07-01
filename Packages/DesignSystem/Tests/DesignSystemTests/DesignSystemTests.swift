import Testing
import SwiftUI
@testable import DesignSystem

@Suite("DesignSystem")
struct DesignSystemTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(DesignSystem.moduleName == "DesignSystem")
    }
}

@Suite("Spacing & Radius tokens")
struct SpacingTests {
    @Test("spacing follows the 4-pt grid, ascending")
    func spacingGrid() {
        let scale = [DSSpacing.xs, DSSpacing.sm, DSSpacing.md, DSSpacing.lg, DSSpacing.xl, DSSpacing.xxl]
        // Every step is a positive multiple of 4.
        for step in scale {
            #expect(step > 0)
            #expect(step.truncatingRemainder(dividingBy: 4) == 0)
        }
        // Strictly increasing.
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
        // Named anchors from the spec.
        #expect(DSSpacing.xs == 4)
        #expect(DSSpacing.xxl == 48)
    }

    @Test("radius tokens ascend and pill is effectively infinite")
    func radiusScale() {
        #expect(DSRadius.sm < DSRadius.md)
        #expect(DSRadius.md < DSRadius.lg)
        #expect(DSRadius.lg < DSRadius.xl)
        #expect(DSRadius.pill >= 999)
    }
}

@Suite("Motion")
struct MotionTests {
    @Test("gated returns the animation when Reduce Motion is off")
    func gatedMotionEnabled() {
        #expect(DSMotion.gated(DSMotion.spring, reduceMotion: false) != nil)
    }

    @Test("gated returns nil when Reduce Motion is on")
    func gatedMotionDisabled() {
        #expect(DSMotion.gated(DSMotion.spring, reduceMotion: true) == nil)
    }

    @Test("durations ascend from quick to slow")
    func durationOrder() {
        #expect(DSMotion.quick < DSMotion.standard)
        #expect(DSMotion.standard < DSMotion.slow)
    }
}

@Suite("ThemeMode")
struct ThemeModeTests {
    @Test("system follows the system (nil color scheme)")
    func systemMode() {
        #expect(ThemeMode.system.colorScheme == nil)
    }

    @Test("light and dark pin the matching color scheme")
    func explicitModes() {
        #expect(ThemeMode.light.colorScheme == .light)
        #expect(ThemeMode.dark.colorScheme == .dark)
    }

    @Test("all cases are stably identified by raw value")
    func identity() {
        #expect(ThemeMode.allCases.map(\.id) == ["system", "light", "dark"])
    }
}

@Suite("ToastStyle")
struct ToastStyleTests {
    @Test("each style maps to a distinct glyph and tint")
    func mapping() {
        let styles: [ToastStyle] = [.info, .success, .warning, .danger]
        let glyphs = styles.map(\.systemImage)
        #expect(Set(glyphs).count == styles.count)
        #expect(ToastStyle.success.systemImage == "checkmark.circle.fill")
        #expect(ToastStyle.danger.tint == DSColor.danger)
    }

    @Test("toast data identity replaces on new value")
    func distinctIdentity() {
        let a = ToastData(style: .info, message: "hi")
        let b = ToastData(style: .info, message: "hi")
        #expect(a != b)
        #expect(a == a)
    }
}
