import SwiftUI
import DesignSystem
import NotificationsFeature

// MARK: - Push notification section helpers

extension SettingsView {

    @ViewBuilder
    var pushSection: some View {
        if let status = pushStatus {
            Section("Notifications") {
                HStack {
                    Label("Status", systemImage: pushStatusIcon(status))
                        .foregroundStyle(Color.cfLabel)
                    Spacer()
                    Text(pushStatusLabel(status))
                        .font(.cfSubheadline)
                        .foregroundStyle(pushStatusColor(status))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Push notification status: \(pushStatusLabel(status))")

                if status == .denied {
                    Button(action: { onManagePushSettings?() }) {
                        Label("Enable in Settings", systemImage: "arrow.up.right")
                            .foregroundStyle(Color.cfAccent)
                    }
                    .accessibilityLabel("Open iOS Settings to enable push notifications")
                }

                if let error = pushRegistrationError {
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

                if let notifModel = notificationSettingsModel {
                    NavigationLink {
                        NotificationSettingsView(model: notifModel)
                    } label: {
                        Label("Notification Preferences", systemImage: "bell.and.waves.left.and.right")
                            .foregroundStyle(Color.cfLabel)
                    }
                    .accessibilityLabel("Open notification preferences")
                    .accessibilityHint("Manage reminders, digests, and alert types")
                }
            }
        }
    }

    func pushStatusLabel(_ status: NotificationPermissionStatus) -> String {
        switch status {
        case .authorized: return "On"
        case .provisional: return "Provisional"
        case .denied: return "Off"
        case .notDetermined: return "Not set"
        case .ephemeral: return "Ephemeral"
        }
    }

    func pushStatusIcon(_ status: NotificationPermissionStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell"
        }
    }

    func pushStatusColor(_ status: NotificationPermissionStatus) -> Color {
        switch status {
        case .authorized, .provisional, .ephemeral: return Color.cfAccent
        case .denied: return Color.orange
        case .notDetermined: return Color.cfSecondaryLabel
        }
    }
}

// MARK: - Share sheet wrapper

#if os(iOS)
import UIKit

/// Wraps `UIActivityViewController` so SwiftUI can present a share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
