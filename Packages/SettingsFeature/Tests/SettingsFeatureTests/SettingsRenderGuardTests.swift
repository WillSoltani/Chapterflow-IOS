// Render-guard snapshot tests for the Settings screen.
//
// Deterministic & hermetic: renders the real screen off-screen with
// `ImageRenderer` (constructed from plain value inputs — no network) and
// asserts a non-empty bitmap. No reference image is committed, so it can't flake
// across renderer versions / CI hosts while still catching layout traps and
// crashes across the light / dark / Dynamic-Type / device-size matrix.
// See docs/VISUAL-QA.md.

import SwiftUI
import Testing
@testable import SettingsFeature

// MARK: - Shared render-guard harness

@MainActor
private func assertRenders(
    _ view: some View,
    _ label: Comment,
    size: CGSize = RenderDevice.phone
) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
#if canImport(AppKit)
    #expect(renderer.nsImage != nil, label)
#else
    #expect(renderer.uiImage != nil, label)
#endif
}

private enum RenderDevice {
    static let se = CGSize(width: 320, height: 568)
    static let phone = CGSize(width: 393, height: 852)
    static let proMax = CGSize(width: 440, height: 956)
    static let ipad = CGSize(width: 834, height: 1112)
}

@MainActor
private func assertMatrix<V: View>(_ name: String, _ make: () -> V) {
    assertRenders(make().environment(\.colorScheme, .light), "\(name) — light")
    assertRenders(make().environment(\.colorScheme, .dark), "\(name) — dark")
    assertRenders(make().environment(\.dynamicTypeSize, .xSmall), "\(name) — XS type")
    assertRenders(make().environment(\.dynamicTypeSize, .accessibility5), "\(name) — AX5 type")
    assertRenders(make(), "\(name) — iPhone SE", size: RenderDevice.se)
    assertRenders(make(), "\(name) — Pro Max", size: RenderDevice.proMax)
    assertRenders(make(), "\(name) — iPad", size: RenderDevice.ipad)
    assertRenders(make().environment(\.layoutDirection, .rightToLeft), "\(name) — RTL")
}

// MARK: - Settings

@MainActor
@Suite("Settings — render guards")
struct SettingsRenderGuardTests {

    @Test("SettingsView renders across the matrix (free user)")
    func freeMatrix() {
        assertMatrix("Settings (free)") {
            NavigationStack {
                SettingsView(isPro: false, remainingFreeStarts: 3)
            }
        }
    }

    @Test("SettingsView renders the Pro state")
    func proMatrix() {
        assertMatrix("Settings (Pro)") {
            NavigationStack {
                SettingsView(
                    isPro: true,
                    currentPeriodEnd: Date(timeIntervalSince1970: 1_800_000_000),
                    cancelAtPeriodEnd: false
                )
            }
        }
    }
}
