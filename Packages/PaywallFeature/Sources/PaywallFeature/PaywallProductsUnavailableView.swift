import SwiftUI
import DesignSystem

struct PaywallProductsUnavailableView: View {
    let availability: ProductAvailabilityState
    let onRetry: () -> Void

    var body: some View {
        CFEmptyState(
            systemImage: systemImage,
            title: "Subscriptions Unavailable",
            description: availability.userMessage,
            actionLabel: availability.canRetry ? "Try Again" : nil,
            action: onRetry
        )
        .accessibilityElement(children: .contain)
    }

    private var systemImage: String {
        switch availability {
        case .networkUnavailable:
            return "wifi.slash"
        case .configurationInvalid:
            return "gear.badge.xmark"
        case .storeUnavailable:
            return "cart.badge.questionmark"
        case .idle, .loading, .available:
            return "cart"
        }
    }
}

#Preview("Configuration invalid · AX5", traits: .fixedLayout(width: 320, height: 568)) {
    PaywallProductsUnavailableView(
        availability: .configurationInvalid,
        onRetry: {}
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
