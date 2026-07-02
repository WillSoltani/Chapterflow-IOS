import Foundation
import Observation
import CoreKit
import Networking
import Persistence

/// Manages the Cognito session lifecycle for the entire app.
///
/// `SessionManager` is the single observable source of truth for `AuthState`.
/// It wraps `AuthService` (Amplify operations) and adds:
/// - Session init / sign-out
/// - BGTask pre-refresh scheduling
/// - Step-up re-authentication (suspends API requests until the user confirms)
/// - Non-destructive `.reconnecting` state when the verifier is unavailable
///
/// **State machine:**
/// - `.unknown`       → after `configure()` → `.signedOut` or `.signedIn(user)`
/// - `.signedOut`     + sign-in success       → `.signedIn(user)`
/// - `.signedIn`      + refresh fails          → `.signedOut`
/// - `.signedIn`      + server reauthRequired → `.reauthRequired`
/// - `.reauthRequired`+ user confirms          → `.signedIn(user)` (request retried)
/// - `.reauthRequired`+ user cancels           → `.signedOut`
/// - `.signedIn`      + verifier exhausted     → `.reconnecting`
/// - `.reconnecting`  + refresh succeeds       → `.signedIn(user)`
@Observable
@MainActor
public final class SessionManager {

    // MARK: - Public state

    public private(set) var authState: AuthState

    // MARK: - Internal (accessible to AuthTokenProvider and BGTask)

    let tokenStore: any TokenStoring

    // MARK: - Live auth service

    let authService: AuthService?

    // MARK: - Test-only refresh path

    private let testRefresher: (any TokenRefreshing)?

    // MARK: - Step-up reauth

    private var reauthContinuations: [CheckedContinuation<Void, Error>] = []
    private var isReauthInProgress = false
    private var currentUser: UserSummary?

    // MARK: - Event listener

    // nonisolated(unsafe): Task.cancel() is safe from any thread.
    // @Observable's macro expansion requires (unsafe) for mutable stored properties.
    nonisolated(unsafe) private var authEventsTask: Task<Void, Never>?

    // MARK: - Production init

    public init(authService: AuthService) {
        self.authService = authService
        self.tokenStore = authService.tokenStore
        self.testRefresher = nil
        // Start .unknown; configure() resolves to .signedIn or .signedOut via events.
        self.authState = .unknown
    }

    // MARK: - Test init (no Amplify)

    public init(
        tokenStore: any TokenStoring,
        refresher: any TokenRefreshing = StubTokenRefresher()
    ) {
        self.authService = nil
        self.testRefresher = refresher
        self.tokenStore = tokenStore
        if let tokens = tokenStore.load(), !tokens.isExpired() {
            let stub = UserSummary(userId: "", username: "test", email: nil)
            self.authState = .signedIn(stub)
            self.currentUser = stub
        } else {
            self.authState = .signedOut
        }
    }

    deinit {
        authEventsTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Configures Amplify (production only) and starts listening to auth events.
    /// Call once at app launch, from `AppModel.configure()`.
    public func configure() throws {
        guard let authService else { return }
        try authService.configure()
        // Capture the stream directly so the task doesn't hold `self` strongly
        // between event arrivals. The `guard let self` inside the loop allows
        // the task to exit cleanly if `SessionManager` is deallocated.
        let eventsStream = authService.authEvents
        authEventsTask = Task { [weak self] in
            for await event in eventsStream {
                guard let self else { return }
                self.handleAuthEvent(event)
            }
        }
    }

    private func handleAuthEvent(_ event: AuthEvent) {
        switch event {
        case .signedIn(let user):
            currentUser = user
            authState = .signedIn(user)
        case .signedOut, .sessionExpired:
            currentUser = nil
            authState = .signedOut
            failAllReauthContinuations()
        case .tokenRefreshed:
            if case .reconnecting = authState, let user = currentUser {
                authState = .signedIn(user)
            }
        }
    }

    // MARK: - Sign-out

    public func signOut() async {
        if let authService {
            await authService.signOut()
            // authState updated via .signedOut event
        } else {
            try? tokenStore.delete()
            currentUser = nil
            authState = .signedOut
            failAllReauthContinuations()
        }
    }

    // MARK: - Step-up reauth (invoked from ReauthView)

    /// Called after the user successfully completes the step-up challenge.
    /// Resumes all suspended API requests and returns to `.signedIn`.
    public func stepUpCompleted() {
        let user = currentUser ?? UserSummary(userId: "", username: "", email: nil)
        authState = .signedIn(user)
        isReauthInProgress = false
        resumeAllReauthContinuations()
    }

    /// Called when the user cancels the reauth sheet. Signs the user out.
    public func stepUpCancelled() {
        Task { await signOut() }
    }

    // MARK: - Reconnecting recovery

    public func markReconnected() {
        if case .reconnecting = authState, let user = currentUser {
            authState = .signedIn(user)
        }
    }

    /// Returns the cached Cognito id_token, or `nil` if none is stored.
    /// Used by `AppModel` to extract display-name JWT claims on sign-in.
    public func currentIdToken() -> String? {
        tokenStore.load()?.idToken
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

// MARK: - TokenRefreshing (used by AuthTokenProvider + BGTask)

extension SessionManager: TokenRefreshing {
    public func performRefresh() async throws -> StoredTokens {
        if let authService {
            // Production path: Amplify performs the refresh and AuthService writes to
            // the TokenStore. This is the single production write path for token storage.
            return try await authService.performRefresh()
        } else if let testRefresher {
            // Test-only path (authService == nil): no Amplify is available, so we write
            // the stub tokens ourselves. This branch is unreachable in production.
            let tokens = try await testRefresher.performRefresh()
            try? tokenStore.save(tokens)
            return tokens
        }
        throw AppError.unauthenticated
    }
}

// MARK: - TokenProviding (wired into APIClient)

extension SessionManager: TokenProviding {

    public func validToken() async throws -> String? {
        guard let tokens = tokenStore.load(), !tokens.isExpired() else { return nil }
        return tokens.idToken
    }

    public func refresh() async throws {
        do {
            _ = try await performRefresh()
        } catch {
            await signOut()
            throw AppError.unauthenticated
        }
    }

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

    public func reportSessionError(_ error: AppError) async {
        switch error {
        case .verifierUnavailable:
            if case .signedIn = authState { authState = .reconnecting }
        default:
            break
        }
    }
}
