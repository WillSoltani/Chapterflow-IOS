/// AuthKit — Cognito authentication + auth UI for ChapterFlow.
///
/// Public surface:
/// - `AuthService`       — `@Observable @MainActor` service; call `configure()` at app launch.
/// - `AuthTokenProvider` — `actor` implementing `Networking.TokenProviding`; inject into `APIClient`.
/// - `TokenRefreshing`   — protocol for the refresh path (injectable in tests).
/// - `AuthState`         — `.unknown / .signedOut / .signedIn(UserSummary)`.
/// - `AuthEvent`         — discrete events streamed from `AuthService.authEvents`.
/// - `SignUpStep`        — result of `AuthService.signUp(…)`.
/// - `UserSummary`       — value type snapshot of the signed-in user.
/// - `TimeProvider`      — clock abstraction for testable token-expiry logic.
/// - `AuthFlowModel`     — `@Observable @MainActor` model driving all auth screens.
/// - `AuthFlowView`      — root `NavigationStack` presenting the full auth flow (iOS).
/// - `PasswordStrength`  — heuristic scorer for password-strength feedback.
public enum AuthKit {}
