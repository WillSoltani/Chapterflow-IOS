import Foundation

/// The application-wide authentication state driven by `SessionManager`.
public enum AuthState: Sendable, Equatable {
    /// Not yet determined — initial check in progress at app launch.
    case unknown
    /// No valid session; the user must sign in.
    case signedOut
    /// Authenticated with a valid Cognito session.
    case signedIn(UserSummary)
    /// Session exists but step-up authentication is required (e.g. the server
    /// returned `reauth_required`). The in-flight request is transparently
    /// retried after the user confirms their identity.
    case reauthRequired
    /// The Cognito verifier is temporarily unavailable. The user stays signed
    /// in; a non-destructive "reconnecting" indicator is shown until recovery.
    case reconnecting
}

/// Discrete events emitted by `AuthService.authEvents`.
public enum AuthEvent: Sendable {
    case signedIn(UserSummary)
    case signedOut
    /// Token was silently refreshed.
    case tokenRefreshed
    /// Session expired and could not be refreshed; routes to sign-in.
    case sessionExpired
}

/// The next required step after a sign-up attempt.
public enum SignUpStep: Sendable, Equatable {
    /// Verification code was sent to the user's email.
    case confirmationRequired
    /// Sign-up is complete (no confirmation needed).
    case done
}
