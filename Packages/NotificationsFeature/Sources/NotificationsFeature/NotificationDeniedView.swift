import SwiftUI
import DesignSystem

/// Recovery screen shown when the user has previously denied notification permission.
///
/// The OS will not re-show its permission dialog, so we explain the impact and
/// deep-link to the app's System Settings page where the user can re-enable.
public struct NotificationDeniedView: View {
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: .cfSpacing64)
            deniedIcon
            Spacer(minLength: .cfSpacing24)
            deniedCopy
            Spacer(minLength: .cfSpacing40)
            settingsButton
            Spacer()
        }
        .padding(.horizontal, .cfSpacing24)
        .background(Color.cfBackground)
    }

    // MARK: - Icon

    private var deniedIcon: some View {
        ZStack {
            Circle()
                .fill(Color.cfSecondaryBackground)
                .frame(width: 88, height: 88)
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Copy

    private var deniedCopy: some View {
        VStack(spacing: .cfSpacing12) {
            Text("Notifications are Off")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
            Text("To receive reading reminders and streak alerts, enable notifications for ChapterFlow in Settings.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Settings CTA

    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Label("Open Settings", systemImage: "arrow.up.right.square")
                .font(.cfHeadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, .cfSpacing4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.cfAccent)
        .accessibilityLabel("Open Settings to enable notifications")
        .accessibilityHint("Opens the ChapterFlow section in the iOS Settings app")
    }

    // MARK: - Private

    private func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
        #endif
    }
}

// MARK: - Previews

#Preview("Denied — Light") {
    NotificationDeniedView()
}

#Preview("Denied — Dark") {
    NotificationDeniedView()
        .preferredColorScheme(.dark)
}

#Preview("Denied — XXL Text") {
    NotificationDeniedView()
        .dynamicTypeSize(.accessibility3)
}
