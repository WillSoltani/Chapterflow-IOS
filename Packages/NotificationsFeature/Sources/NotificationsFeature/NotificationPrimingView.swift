import SwiftUI
import DesignSystem

/// The permission priming sheet shown before the OS authorization dialog.
///
/// Present when `NotificationPrimingCoordinator.isPrimingVisible == true`.
/// The user must tap "Enable" or "Not Now" to dismiss.
public struct NotificationPrimingView: View {

    private let onEnable: () async -> Void
    private let onNotNow: () -> Void

    public init(
        onEnable: @escaping () async -> Void,
        onNotNow: @escaping () -> Void
    ) {
        self.onEnable = onEnable
        self.onNotNow = onNotNow
    }

    public var body: some View {
        VStack(spacing: .cfSpacing24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            VStack(spacing: .cfSpacing8) {
                Text("Stay on track with ChapterFlow")
                    .font(.cfTitle2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.cfLabel)

                Text("Get reminders for your reading streak, upcoming reviews, and chapters you've committed to finishing.")
                    .font(.cfBody)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .padding(.horizontal, .cfSpacing8)
            }

            Spacer()

            VStack(spacing: .cfSpacing12) {
                Button {
                    Task { await onEnable() }
                } label: {
                    Text("Enable Notifications")
                        .font(.cfSubheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .cfSpacing12)
                        .background(Color.cfAccent, in: RoundedRectangle(cornerRadius: .cfRadius12))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Enable push notifications")

                Button(action: onNotNow) {
                    Text("Not Now")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .padding(.vertical, .cfSpacing8)
                }
                .accessibilityLabel("Dismiss notification prompt")
            }
        }
        .padding(.horizontal, .cfSpacing24)
        .padding(.bottom, .cfSpacing32)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Priming sheet — light") {
    NotificationPrimingView(
        onEnable: {},
        onNotNow: {}
    )
}

#Preview("Priming sheet — dark") {
    NotificationPrimingView(
        onEnable: {},
        onNotNow: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Priming sheet — XXL text") {
    NotificationPrimingView(
        onEnable: {},
        onNotNow: {}
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
