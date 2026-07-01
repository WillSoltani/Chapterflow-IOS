import Foundation

/// The application-wide authentication state driven by `AuthService`.
public enum AuthState: Sendable, Equatable {
    /// Not yet determined — check in progress at app launch.
    case unknown
    /// No valid session; the user must sign in.
    case signedOut
    /// Authenticated with a valid session.
    case signedIn(UserSummary)
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
