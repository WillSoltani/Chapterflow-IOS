import Foundation
import Observation
import CoreKit
import Networking

/// Manages the Cognito session lifecycle for the entire app.
///
/// `SessionManager` is the single source of truth for `AuthState`. It
/// implements `TokenProviding` so it is injected directly into `APIClient` —
/// the client calls back into it for token access, refresh, step-up reauth,
/// and error notification.
///
/// **State machine:**
/// - `.signedOut`      + sign-in success       → `.signedIn`
/// - `.signedIn`       + refresh fails          → `.signedOut`
/// - `.signedIn`       + server reauth_required → `.reauthRequired`
/// - `.reauthRequired` + user confirms          → `.signedIn`  (original request retried)
/// - `.reauthRequired` + user cancels           → `.signedOut`
/// - `.signedIn`       + verifier exhausted     → `.reconnecting`
/// - `.reconnecting`   + next request succeeds  → `.signedIn`
@Observable
@MainActor
public final class SessionManager {

    // MARK: - Public state

    public private(set) var authState: AuthState

    // MARK: - Private

    let tokenStore: any TokenStoring
    private let refresher: any TokenRefreshing

    private var reauthContinuations: [CheckedContinuation<Void, Error>] = []
    private var isReauthInProgress = false

    // MARK: - Init

    public init(
        tokenStore: any TokenStoring = KeychainTokenStore.shared,
        refresher: any TokenRefreshing = StubTokenRefresher()
    ) {
        self.tokenStore = tokenStore
        self.refresher = refresher
        self.authState = tokenStore.idToken() != nil ? .signedIn : .signedOut
    }

    // MARK: - Token access

    /// Returns the currently stored Cognito `id_token`, or `nil` when signed out.
    /// Used by the app layer to decode JWT claims (e.g. display name) without
    /// exposing the underlying token store.
    public func currentIdToken() -> String? {
        tokenStore.idToken()
    }

    // MARK: - Session entry/exit

    /// Stores tokens from a successful sign-in and transitions to `.signedIn`.
    public func didSignIn(idToken: String, refreshToken: String) {
        tokenStore.store(idToken: idToken, refreshToken: refreshToken)
        authState = .signedIn
    }

    /// Clears all tokens, cancels any in-progress reauth, and transitions to `.signedOut`.
    public func signOut() {
        tokenStore.clearAll()
        authState = .signedOut
        failAllReauthContinuations()
    }

    // MARK: - Step-up reauth callbacks (invoked from ReauthView)

    /// Called when the user successfully completes step-up re-authentication.
    /// Stores fresh tokens, resumes all suspended API requests, and returns to `.signedIn`.
    public func stepUpCompleted(idToken: String, refreshToken: String) {
        tokenStore.store(idToken: idToken, refreshToken: refreshToken)
        authState = .signedIn
        isReauthInProgress = false
        resumeAllReauthContinuations()
    }

    /// Called when the user cancels the reauth sheet. Signs the user out.
    public func stepUpCancelled() {
        signOut()
    }

    // MARK: - Reconnecting recovery

    /// Marks the session as reconnected after a successful request following
    /// a `.reconnecting` state.
    public func markReconnected() {
        if case .reconnecting = authState { authState = .signedIn }
    }

    // MARK: - Continuation management

    private func failAllReauthContinuations() {
        let continuations = reauthContinuations
        reauthContinuations = []
        isReauthInProgress = false
        for c in continuations { c.resume(throwing: AppError.unauthenticated) }
    }

    private func resumeAllReauthContinuations() {
        let continuations = reauthContinuations
        reauthContinuations = []
        for c in continuations { c.resume() }
    }
}

// MARK: - TokenProviding

extension SessionManager: TokenProviding {

    /// Returns the stored `id_token`, or `nil` when the user is not signed in.
    public func validToken() async throws -> String? {
        tokenStore.idToken()
    }

    /// Attempts a Cognito token refresh using the stored refresh token.
    ///
    /// On failure the user is signed out (setting `authState = .signedOut`)
    /// before re-throwing, so `AppRootView` transitions to the auth flow.
    public func refresh() async throws {
        guard let refreshToken = tokenStore.refreshToken() else {
            signOut()
            throw AppError.unauthenticated
        }
        do {
            let tokens = try await refresher.refreshTokens(using: refreshToken)
            tokenStore.store(idToken: tokens.idToken, refreshToken: tokens.refreshToken)
        } catch {
            signOut()
            throw AppError.unauthenticated
        }
    }

    /// Performs step-up authentication when the server returns `reauth_required`.
    ///
    /// Suspends the calling `APIClient` task until the user completes the
    /// challenge (`stepUpCompleted`) or cancels (`stepUpCancelled`).
    /// On success the client retries the original request transparently.
    public nonisolated func stepUp() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard case .signedIn = authState else {
                    continuation.resume(throwing: AppError.unauthenticated)
                    return
                }
                reauthContinuations.append(continuation)
                if !isReauthInProgress {
                    isReauthInProgress = true
                    authState = .reauthRequired
                }
            }
        }
    }

    /// Called by `APIClient` when the Cognito verifier is permanently unavailable
    /// for this request (all backoff retries exhausted). Transitions to
    /// `.reconnecting` so the UI can show a non-destructive indicator.
    public func reportSessionError(_ error: AppError) async {
        switch error {
        case .verifierUnavailable:
            if case .signedIn = authState { authState = .reconnecting }
        default:
            break
        }
    }
}
