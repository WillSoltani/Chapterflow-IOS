import SwiftUI
import DesignSystem

/// Shown when the server signals the account has been deactivated or deleted.
public struct AccountStatusView: View {

    public enum Status {
        case deactivated
        case deleted
    }

    let status: Status
    let onSignOut: () -> Void

    public init(status: Status, onSignOut: @escaping () -> Void) {
        self.status = status
        self.onSignOut = onSignOut
    }

    public var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.cfTitle2)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button("Sign Out", action: onSignOut)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 52)
                .accessibilityLabel("Sign out of ChapterFlow")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfBackground)
    }

    private var iconName: String {
        switch status {
        case .deactivated: return "person.badge.minus"
        case .deleted:     return "person.slash"
        }
    }

    private var title: String {
        switch status {
        case .deactivated: return "Account Deactivated"
        case .deleted:     return "Account Deleted"
        }
    }

    private var message: String {
        switch status {
        case .deactivated:
            return "Your account has been deactivated. Contact support if you believe this is an error."
        case .deleted:
            return "This account no longer exists. Create a new account to continue reading."
        }
    }
}

#Preview("Account Deactivated") {
    AccountStatusView(status: .deactivated, onSignOut: {})
}

#Preview("Account Deleted") {
    AccountStatusView(status: .deleted, onSignOut: {})
}
