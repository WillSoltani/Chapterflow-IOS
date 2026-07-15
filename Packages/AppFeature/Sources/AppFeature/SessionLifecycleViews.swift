import DesignSystem
import SwiftUI

enum SessionPrivatePresentationGate {
    static func item<Item>(
        _ item: Item?,
        hasActiveMatchingScope: Bool
    ) -> Item? {
        hasActiveMatchingScope ? item : nil
    }
}

enum SessionTransitionKind: Equatable {
    case preparing
    case switchingAccounts
    case signingOut

    var visibleLabel: String {
        switch self {
        case .preparing: "Preparing your library…"
        case .switchingAccounts: "Switching accounts…"
        case .signingOut: "Signing you out…"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .preparing: "Preparing your library"
        case .switchingAccounts: "Switching accounts"
        case .signingOut: "Signing you out"
        }
    }
}

enum SignOutFailureContent {
    static let heading = "Couldn’t sign out"
    static let message = "You’re still signed in. Try again when you’re ready."
    static let retryAction = "Try Again"
    static let cancelAction = "Stay Signed In"
    static let orderedActions = [retryAction, cancelAction]
}

enum SessionScopeRecoveryContent {
    static let heading = "Your library could not be prepared"
    static let message = "Your account data is still protected. Try again, or sign out."
    static let orderedActions = ["Try Again", "Sign Out"]
}

struct SessionScopeRecoveryView: View {
    let onRetry: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(SessionScopeRecoveryContent.heading, systemImage: "exclamationmark.triangle")
                .accessibilityAddTraits(.isHeader)
        } description: {
            Text(SessionScopeRecoveryContent.message)
        } actions: {
            VStack(spacing: .cfSpacing12) {
                Button(SessionScopeRecoveryContent.orderedActions[0], action: onRetry)
                    .buttonStyle(.borderedProminent)
                Button(SessionScopeRecoveryContent.orderedActions[1], action: onSignOut)
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
