/// The session state of the current user.
public enum AuthState: Equatable, Sendable {
    /// A valid Cognito session is active.
    case signedIn
    /// No session present. The auth flow should be presented.
    case signedOut
    /// Session exists but step-up authentication is required (e.g. the server
    /// returned `reauth_required`). The in-flight request is transparently
    /// retried after the user confirms their identity.
    case reauthRequired
    /// The Cognito verifier is temporarily unavailable. The user stays signed
    /// in; a non-destructive "reconnecting" indicator is shown until recovery.
    case reconnecting
}
