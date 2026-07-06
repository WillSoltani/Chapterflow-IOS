import SwiftUI

/// A subtle pill-shaped indicator shown when the device is offline.
///
/// Place it near the top of a screen or inside a `VStack` above content that
/// may be stale. Animates in/out with a slide + fade when `isOffline` changes.
///
/// ```swift
/// OfflineBannerView(isOffline: !reachability.isConnected)
/// ```
public struct OfflineBannerView: View {

    public let isOffline: Bool

    public init(isOffline: Bool) {
        self.isOffline = isOffline
    }

    public var body: some View {
        if isOffline {
            HStack(spacing: .cfSpacing6) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11, weight: .medium))
                Text("Offline")
                    .font(.cfCaption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, .cfSpacing12)
            .padding(.vertical, .cfSpacing6)
            .background(.regularMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityLabel("You are offline. Showing cached content.")
        }
    }
}

// MARK: - Private spacing token

private extension CGFloat {
    static let cfSpacing6: CGFloat = 6
}

// MARK: - Preview

#if DEBUG
#Preview("Offline banner") {
    VStack(spacing: .cfSpacing16) {
        OfflineBannerView(isOffline: true)
        OfflineBannerView(isOffline: false)
        Text("Some content below")
            .font(.cfBody)
    }
    .padding()
}

#Preview("Offline banner — dark") {
    OfflineBannerView(isOffline: true)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Offline banner — XXL") {
    OfflineBannerView(isOffline: true)
        .padding()
        .dynamicTypeSize(.accessibility3)
}
#endif
