// Render-guard snapshot tests for the Paywall screen.
//
// Deterministic & hermetic: renders the real screen off-screen with
// `ImageRenderer` (fed by the in-package preview model helpers — no StoreKit
// network, no live clock) and asserts a non-empty bitmap. No reference image is
// committed, so it can't flake across renderer versions / CI hosts while still
// catching layout traps and crashes across the light / dark / Dynamic-Type /
// device-size matrix. See docs/VISUAL-QA.md.

import SwiftUI
import Testing
@testable import PaywallFeature

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

// MARK: - Paywall

@MainActor
@Suite("Paywall — render guards")
struct PaywallRenderGuardTests {

    @Test("PaywallView renders across the matrix (not subscribed)")
    func notSubscribedMatrix() {
        assertMatrix("Paywall (offer)") {
            PaywallView(previewModel: previewPaywallModel(
                status: .notSubscribed,
                products: previewSampleProducts
            ))
        }
    }

    @Test("PaywallView renders the already-Pro (Apple) state")
    func alreadyProMatrix() {
        assertMatrix("Paywall (Pro)") {
            PaywallView(previewModel: previewPaywallModel(
                status: .subscribed(productID: "com.chapterflow.ios.pro.annual", expirationDate: nil),
                products: previewSampleProducts,
                context: .settings,
                proSource: "apple"
            ))
        }
    }

    @Test("PaywallView renders a fail-closed product state")
    func unavailableProductsMatrix() {
        assertMatrix("Paywall (products unavailable)") {
            let model = previewPaywallModel(status: .notSubscribed, products: [])
            model.inject(
                productInfos: [],
                status: .notSubscribed,
                entitlementResolution: .resolvedFree,
                productAvailability: .configurationInvalid
            )
            return PaywallView(previewModel: model)
        }
    }

    @Test("Paywall success is scroll-safe at AX5 with reduced motion")
    func reducedMotionSuccess() {
        let model = previewPaywallModel(
            status: .notSubscribed,
            products: previewSampleProducts
        )
        let view = PaywallView(
            previewModel: model,
            showSuccessOverlay: true,
            reduceMotionOverride: true
        )
        .environment(\.dynamicTypeSize, .accessibility5)

        assertRenders(view, "Paywall success — AX5 + Reduce Motion", size: RenderDevice.se)
    }

    @Test("preview composition opts out of live loading")
    func previewDoesNotLoad() {
        let view = PaywallView(previewModel: previewPaywallModel(
            status: .notSubscribed,
            products: previewSampleProducts
        ))

        #expect(!view.performsInitialLoad)
    }
}
