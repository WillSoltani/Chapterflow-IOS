import Models

/// Captures the action a guest was attempting when they hit an auth gate.
///
/// Stored in `AppModel.pendingAuthIntent`. After sign-in completes,
/// `AppModel.replayPendingIntent()` executes the stored intent so the user
/// lands exactly where they wanted to be.
public enum AuthGateIntent: Sendable, Equatable {
    /// The user tapped "Start Reading" on a book detail screen.
    case startBook(bookId: String, variantFamily: VariantFamily)
    /// No specific intent — generic "create account" prompt.
    case none

    /// Short human-readable value proposition shown in the auth gate sheet.
    var gateContext: String {
        switch self {
        case .startBook: return "Sign up free to start reading"
        case .none:      return "Create a free account"
        }
    }

    var isNone: Bool {
        if case .none = self { return true }
        return false
    }
}
