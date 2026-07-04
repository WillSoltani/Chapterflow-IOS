import SwiftUI
import DesignSystem

/// Recovery view shown when push authorization is `.denied`.
///
/// Per docs/ios/PUSH-CONTRACT.md: when denied, do not call `requestAuthorization()`.
/// Instead, deep-link the user to `UIApplication.openSettingsURLString`.
public struct NotificationDeniedView: View {

    private let onOpenSettings: () -> Void

    public init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: .cfSpacing24) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityHidden(true)

            VStack(spacing: .cfSpacing8) {
                Text("Notifications are turned off")
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)

                Text("Enable notifications in Settings to receive reading reminders and streak alerts.")
                    .font(.cfBody)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }

            Button(action: onOpenSettings) {
                Label("Open Settings", systemImage: "gear")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfAccent)
            }
            .accessibilityLabel("Open iOS Settings to enable notifications")
        }
        .padding(.cfSpacing24)
    }
}

#if DEBUG
#Preview("Denied — light") {
    NotificationDeniedView(onOpenSettings: {})
}

#Preview("Denied — dark") {
    NotificationDeniedView(onOpenSettings: {})
        .preferredColorScheme(.dark)
}

#Preview("Denied — XXL text") {
    NotificationDeniedView(onOpenSettings: {})
        .dynamicTypeSize(.accessibility3)
}
#endif
