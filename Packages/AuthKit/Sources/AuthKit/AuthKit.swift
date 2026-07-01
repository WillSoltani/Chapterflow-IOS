/// AuthKit — Cognito authentication for ChapterFlow.
///
/// Public surface:
/// - `AuthService`       — `@Observable @MainActor` service; call `configure()` at app launch.
/// - `AuthTokenProvider` — `actor` implementing `Networking.TokenProviding`; inject into `APIClient`.
/// - `TokenRefreshing`   — protocol for the refresh path (injectable in tests).
/// - `AuthState`         — `.unknown / .signedOut / .signedIn(UserSummary)`.
/// - `AuthEvent`         — discrete events streamed from `AuthService.authEvents`.
/// - `SignUpStep`         — result of `AuthService.signUp(…)`.
/// - `UserSummary`       — value type snapshot of the signed-in user.
/// - `TimeProvider`      — clock abstraction for testable token-expiry logic.
public enum AuthKit {}
