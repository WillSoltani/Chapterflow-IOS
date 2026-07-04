import SwiftUI
import UserNotifications
import DesignSystem

/// A settings-row component that displays the current push notification
/// authorization status and offers a shortcut to the system Settings app
/// when notifications are denied.
public struct PushStatusView: View {

    private let status: UNAuthorizationStatus
    private let registrationError: Error?
    private let onOpenSettings: (() -> Void)?

    public init(
        status: UNAuthorizationStatus,
        registrationError: Error? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.status = status
        self.registrationError = registrationError
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        Section("Push Notifications") {
            HStack {
                Label("Status", systemImage: statusIcon)
                    .foregroundStyle(Color.cfLabel)
                Spacer()
                Text(statusLabel)
                    .font(.cfSubheadline)
                    .foregroundStyle(statusColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Push notification status: \(statusLabel)")

            if status == .denied {
                Button(action: { onOpenSettings?() }) {
                    Label("Enable in Settings", systemImage: "arrow.up.right")
                        .foregroundStyle(Color.cfAccent)
                }
                .accessibilityLabel("Open Settings to enable push notifications")
            }

            if let error = registrationError {
                HStack(spacing: .cfSpacing8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                        .accessibilityHidden(true)
                    Text(error.localizedDescription)
                        .font(.cfFootnote)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Registration error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch status {
        case .authorized: return "On"
        case .provisional: return "Provisional"
        case .denied: return "Off"
        case .notDetermined: return "Not set"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private var statusIcon: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell"
        @unknown default: return "bell"
        }
    }

    private var statusColor: Color {
        switch status {
        case .authorized, .provisional, .ephemeral: return Color.cfAccent
        case .denied: return Color.orange
        case .notDetermined: return Color.cfSecondaryLabel
        @unknown default: return Color.cfSecondaryLabel
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Authorized — light") {
    Form { PushStatusView(status: .authorized) }
}

#Preview("Denied with error — dark") {
    Form {
        PushStatusView(
            status: .denied,
            registrationError: URLError(.notConnectedToInternet),
            onOpenSettings: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Not determined — XXL text") {
    Form { PushStatusView(status: .notDetermined) }
        .dynamicTypeSize(.accessibility3)
}
#endif
