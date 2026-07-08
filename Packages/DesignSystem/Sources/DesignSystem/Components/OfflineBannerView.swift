import SwiftUI

/// A subtle pill-shaped indicator shown when the device is offline.
///
/// Place it near the top of a screen or inside a `VStack` above content that
/// may be stale. Animates in/out with a slide + fade when `isOffline` changes.
///
/// ```swift
/// OfflineBannerView(isOffline: !reachability.isConnected, pendingCount: syncStatus.pendingCount)
/// ```
public struct OfflineBannerView: View {

    public let isOffline: Bool
    /// Number of mutations queued in the offline outbox. When > 0, shown in the pill.
    public let pendingCount: Int

    public init(isOffline: Bool, pendingCount: Int = 0) {
        self.isOffline = isOffline
        self.pendingCount = pendingCount
    }

    public var body: some View {
        if isOffline {
            HStack(spacing: .cfSpacing6) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11, weight: .medium))
                Text(pillLabel)
                    .font(.cfCaption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, .cfSpacing12)
            .padding(.vertical, .cfSpacing6)
            .background(.regularMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityLabel(accessLabel)
        }
    }

    private var pillLabel: String {
        pendingCount > 0 ? "Offline · \(pendingCount) queued" : "Offline"
    }

    private var accessLabel: String {
        switch pendingCount {
        case 0:
            return "You are offline. Showing cached content."
        case 1:
            return "You are offline. 1 change queued to sync."
        default:
            return "You are offline. \(pendingCount) changes queued to sync."
        }
    }
}

// MARK: - Private spacing token

private extension CGFloat {
    static let cfSpacing6: CGFloat = 6
}

// MARK: - Preview

#if DEBUG
#Preview("Offline banner — no queue") {
    VStack(spacing: .cfSpacing16) {
        OfflineBannerView(isOffline: true)
        OfflineBannerView(isOffline: false)
        Text("Some content below")
            .font(.cfBody)
    }
    .padding()
}

#Preview("Offline banner — with queue") {
    OfflineBannerView(isOffline: true, pendingCount: 5)
        .padding()
}

#Preview("Offline banner — dark") {
    OfflineBannerView(isOffline: true, pendingCount: 2)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Offline banner — XXL") {
    OfflineBannerView(isOffline: true, pendingCount: 3)
        .padding()
        .dynamicTypeSize(.accessibility3)
}
#endif
