import SwiftUI

// MARK: - Offline disabled modifier

/// Disables a view and surfaces a "Requires internet" reason label when the device
/// is offline. Apply to online-only actions (e.g. purchasing Pro, submitting an AI ask
/// with no on-device fallback) so the user gets a clear explanation instead of a silent no-op.
///
/// ```swift
/// Button("Upgrade to Pro") { showPaywall() }
///     .offlineDisabled(isOffline: !reachability.isConnected)
/// ```
public struct OfflineDisabledModifier: ViewModifier {
    public let isOffline: Bool
    public let reason: String

    public func body(content: Content) -> some View {
        content
            .disabled(isOffline)
            .overlay(alignment: .bottom) {
                if isOffline {
                    OfflineReasonLabel(text: reason)
                        .offset(y: 28)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isOffline)
    }
}

public extension View {
    /// Disables this view and shows a "Requires internet" explanation when `isOffline` is true.
    ///
    /// Use for online-only actions such as purchasing a subscription or triggering
    /// a server-side AI response with no local fallback.
    func offlineDisabled(
        isOffline: Bool,
        reason: String = "Requires internet connection"
    ) -> some View {
        modifier(OfflineDisabledModifier(isOffline: isOffline, reason: reason))
    }
}

// MARK: - Offline reason label

/// A small capsule label shown below a disabled control when offline.
private struct OfflineReasonLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "wifi.slash")
                .font(.caption2.weight(.medium))
                .accessibilityHidden(true)
            Text(text)
                .font(.cfCaption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, .cfSpacing8)
        .padding(.vertical, .cfSpacing4)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel(text)
    }
}

// MARK: - Offline queued badge

/// A compact badge indicating that offline mutations are queued for sync.
///
/// Place inline with a button or action group to communicate that the user's
/// writable actions are safely held in the outbox and will sync on reconnect.
///
/// ```swift
/// HStack {
///     Button("Save note") { saveNote() }
///     if isOffline { OfflineQueuedBadge(pendingCount: syncStatus.pendingCount) }
/// }
/// ```
public struct OfflineQueuedBadge: View {
    public let pendingCount: Int

    public init(pendingCount: Int) {
        self.pendingCount = pendingCount
    }

    public var body: some View {
        if pendingCount > 0 {
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "arrow.up.circle.dotted")
                    .font(.caption2.weight(.medium))
                    .accessibilityHidden(true)
                Text(badgeText)
                    .font(.cfCaption2)
            }
            .foregroundStyle(Color.cfSecondaryLabel)
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, .cfSpacing4)
            .background(Color.cfSecondaryFill, in: Capsule())
            .accessibilityLabel(accessibilityLabel)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private var badgeText: String {
        pendingCount == 1 ? "1 queued" : "\(pendingCount) queued"
    }

    private var accessibilityLabel: String {
        pendingCount == 1
            ? "1 change queued, will sync when back online"
            : "\(pendingCount) changes queued, will sync when back online"
    }
}

// MARK: - Queued confirmation toast helper

/// Shows a brief "queued" toast anchored to the top when `isPresented` is true.
///
/// The toast auto-dismisses after `duration` seconds. Wire it to an `onChange`
/// that watches `syncStatus.pendingCount` while offline:
///
/// ```swift
/// .offlineQueuedToast(isPresented: $showQueuedToast)
/// .onChange(of: syncStatus.pendingCount) { old, new in
///     guard isOffline, new > old else { return }
///     showQueuedToast = true
/// }
/// ```
public struct OfflineQueuedToastModifier: ViewModifier {
    @Binding public var isPresented: Bool

    public func body(content: Content) -> some View {
        content
            .cfToast(
                "Saved offline — will sync when reconnected",
                systemImage: "arrow.up.circle.dotted",
                isPresented: isPresented
            )
    }
}

public extension View {
    /// Overlays an auto-dismissing "queued offline" toast.
    func offlineQueuedToast(isPresented: Binding<Bool>) -> some View {
        modifier(OfflineQueuedToastModifier(isPresented: isPresented))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Offline disabled — modifier") {
    VStack(spacing: .cfSpacing24) {
        Button("Upgrade to Pro") {}
            .buttonStyle(.borderedProminent)
            .offlineDisabled(isOffline: true)

        Button("Ask AI") {}
            .buttonStyle(.bordered)
            .offlineDisabled(isOffline: true, reason: "AI requires an internet connection")

        Button("Online action — enabled") {}
            .buttonStyle(.bordered)
            .offlineDisabled(isOffline: false)
    }
    .padding(.cfSpacing32)
}

#Preview("Offline disabled — dark") {
    Button("Upgrade to Pro") {}
        .buttonStyle(.borderedProminent)
        .offlineDisabled(isOffline: true)
        .padding(.cfSpacing32)
        .preferredColorScheme(.dark)
}

#Preview("Offline disabled — XXL") {
    Button("Upgrade to Pro") {}
        .buttonStyle(.borderedProminent)
        .offlineDisabled(isOffline: true)
        .padding(.cfSpacing32)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Queued badge — counts") {
    VStack(spacing: .cfSpacing12) {
        OfflineQueuedBadge(pendingCount: 0)
        OfflineQueuedBadge(pendingCount: 1)
        OfflineQueuedBadge(pendingCount: 7)
    }
    .padding()
}

#Preview("Queued badge — dark") {
    OfflineQueuedBadge(pendingCount: 3)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Queued badge — XXL") {
    OfflineQueuedBadge(pendingCount: 3)
        .padding()
        .dynamicTypeSize(.accessibility3)
}
#endif
