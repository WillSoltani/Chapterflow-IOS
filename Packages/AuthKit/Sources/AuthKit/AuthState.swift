import Foundation

/// The application-wide authentication state driven by `SessionManager`.
public enum AuthState: Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Not yet determined — initial check in progress at app launch.
    case unknown
    /// No valid session; the user must sign in.
    case signedOut
    /// Authenticated with a valid Cognito session.
    case signedIn(SessionIdentity)
    /// Session exists but step-up authentication is required (e.g. the server
    /// returned `reauth_required`). The in-flight request is transparently
    /// retried after the user confirms their identity.
    case reauthRequired
    /// The Cognito verifier is temporarily unavailable. The user stays signed
    /// in; a non-destructive "reconnecting" indicator is shown until recovery.
    case reconnecting

    public var description: String {
        switch self {
        case .unknown: "AuthState.unknown"
        case .signedOut: "AuthState.signedOut"
        case .signedIn: "AuthState.signedIn(redacted)"
        case .reauthRequired: "AuthState.reauthRequired"
        case .reconnecting: "AuthState.reconnecting"
        }
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["state": description])
    }
}

/// The next required step after a sign-up attempt.
public enum SignUpStep: Sendable, Equatable {
    /// Verification code was sent to the user's email.
    case confirmationRequired
    /// Sign-up is complete (no confirmation needed).
    case done
}
