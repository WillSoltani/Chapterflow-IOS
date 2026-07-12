import SwiftUI
import Testing
import DesignSystem
@testable import PaywallFeature

@MainActor
@Suite("WP-REL-01 paywall release snapshots", .serialized)
struct ReleaseVisualSnapshotTests {
    private let smallPhone = CGSize(width: 320, height: 568)

    @Test("fail-closed products remain clear at AX5 on a small phone")
    func failClosedProducts() throws {
        let view = unavailableSurface
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.locale, Locale(identifier: "en_US"))

        try assertReferenceSnapshot(
            view,
            named: "fail-closed-products-small-phone-ax5",
            size: smallPhone
        )
    }

#if canImport(UIKit)
    @Test("full fail-closed product copy remains reachable at AX5")
    func failClosedProductsBottom() throws {
        let view = unavailableSurface
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: "en_US"))

        try assertReferenceSnapshot(
            view,
            named: "fail-closed-products-bottom-small-phone-ax5",
            size: smallPhone,
            scrollPosition: .bottom
        )
    }
#endif

    @Test("success overlay remains scroll-safe at AX5 with reduced motion")
    func reducedMotionSuccess() throws {
        let view = PaywallSuccessOverlay(
            isActive: true,
            reduceMotion: true,
            onContinue: {}
        )
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.locale, Locale(identifier: "en_US"))

        try assertReferenceSnapshot(
            view,
            named: "success-reduced-motion-small-phone-ax5",
            size: smallPhone
        )
    }

#if canImport(UIKit)
    @Test("success action remains reachable at AX5 with reduced motion")
    func reducedMotionSuccessBottom() throws {
        let view = PaywallSuccessOverlay(
            isActive: true,
            reduceMotion: true,
            onContinue: {}
        )
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.locale, Locale(identifier: "en_US"))

        try assertReferenceSnapshot(
            view,
            named: "success-reduced-motion-bottom-small-phone-ax5",
            size: smallPhone,
            scrollPosition: .bottom
        )
    }
#endif

    private var unavailableSurface: some View {
        ZStack {
            Color.cfGroupedBackground.ignoresSafeArea()

            ScrollView {
                PaywallProductsUnavailableView(
                    availability: .configurationInvalid,
                    onRetry: {}
                )
                .padding(.horizontal, .cfSpacing20)
                .padding(.vertical, .cfSpacing32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
