import CoreKit
import Foundation
import Networking
import Observation
import Persistence
/// The single authority for Cognito session state and the token mirror.
@Observable
@MainActor
public final class SessionManager {
    public private(set) var authState: AuthState
    public private(set) var currentIdentity: SessionIdentity?

    let tokenStore: any TokenStoring
    let authService: AuthService?

    @ObservationIgnored private let testRefresher: (any TokenRefreshing)?
    @ObservationIgnored var hermeticSignOut: (@MainActor @Sendable () async -> Bool)? = nil
    @ObservationIgnored private var sessionGeneration: UInt64 = 0
    @ObservationIgnored private var restorationTask: Task<Void, Never>?
    @ObservationIgnored private var signInFlight: SignInFlight?
    @ObservationIgnored private var refreshFlight: RefreshFlight?
    @ObservationIgnored private var stepUpWaiters: [UUID: StepUpWaiter] = [:]
    @ObservationIgnored private var isSigningOut = false

    public init(authService: AuthService) {
        self.authService = authService
        self.tokenStore = authService.tokenStore
        self.testRefresher = nil
        self.authState = .unknown
        self.currentIdentity = nil
    }

    public init(
        tokenStore: any TokenStoring,
        refresher: any TokenRefreshing = StubTokenRefresher()
    ) {
        self.authService = nil
        self.tokenStore = tokenStore
        self.testRefresher = refresher
        self.authState = .signedOut
        self.currentIdentity = nil
    }

    init(
        tokenStore: any TokenStoring,
        refresher: any TokenRefreshing,
        testIdentity: SessionIdentity
    ) {
        self.authService = nil
        self.tokenStore = tokenStore
        self.testRefresher = refresher
        self.authState = .signedIn(testIdentity)
        self.currentIdentity = testIdentity
    }

    init(authService: AuthService, testIdentity: SessionIdentity) {
        self.authService = authService
        self.tokenStore = authService.tokenStore
        self.testRefresher = nil
        self.authState = .signedIn(testIdentity)
        self.currentIdentity = testIdentity
    }

    func establishSessionForTesting(
        identity: SessionIdentity,
        tokens: StoredTokens
    ) throws {
        _ = beginNewGeneration()
        try tokenStore.save(tokens)
        currentIdentity = identity
        authState = .signedIn(identity)
    }

    isolated deinit {
        restorationTask?.cancel()
        if let flight = refreshFlight {
            flight.task?.cancel()
            for continuation in flight.waiters.values {
                continuation.resume(throwing: CancellationError())
            }
        }
        for waiter in stepUpWaiters.values {
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    public func configure() throws {
        guard !isSigningOut else { throw AppError.unauthenticated }
        #if DEBUG
        if Self.isHermeticUITestBypass(environment: ProcessInfo.processInfo.environment) {
            establishHermeticUITestSession()
            return
        }
        #endif

        guard let authService else { return }
        try authService.configure()
        // Configuration may be called defensively more than once. Never let a
        // restoration task replace an already-authoritative live identity.
        guard currentIdentity == nil else { return }
        _ = startRestoration(using: authService)
    }

    func restoreSession() async {
        guard currentIdentity == nil else { return }
        guard let authService else {
            transitionToSignedOut(clearMirror: true)
            return
        }
        let task = startRestoration(using: authService)
        await task.value
    }

    /// Routes email sign-in through the same verified session boundary used by
    /// restoration and refresh.
    public func signIn(username: String, password: String) async throws {
        // Cognito/Amplify does not support replacing one active user in place.
        // More importantly, A-owned teardown (including APNs unregister) needs
        // A's bearer token. Require the app's existing deterministic sign-out
        // transaction to finish before any B sign-in may begin.
        guard !isSigningOut,
              signInFlight == nil,
              currentIdentity == nil,
              authState == .unknown || authState == .signedOut,
              let authService else {
            throw AppError.unauthenticated
        }
        let generation = beginNewGeneration()
        currentIdentity = nil
        if authState != .signedOut { authState = .signedOut }

        let flightID = UUID()
        let task = Task { @MainActor [authService] in
            try await authService.signIn(username: username, password: password)
        }
        signInFlight = SignInFlight(id: flightID, generation: generation, task: task)

        do {
            let candidate = try await task.value
            clearSignInFlight(flightID)
            guard generation == sessionGeneration else { throw CancellationError() }
            try commit(candidate, generation: generation)
        } catch {
            clearSignInFlight(flightID)
            guard generation == sessionGeneration else { throw CancellationError() }
            await failClosed(generation: generation, using: authService)
            throw error
        }
    }

    /// Invalidates in-flight work immediately, then reports signed out only
    /// after Amplify confirms that its local Cognito session was cleared.
    @discardableResult
    public func signOut() async -> Bool {
        guard !isSigningOut else { return false }
        let previousIdentity = currentIdentity
        let generation = beginNewGeneration()
        isSigningOut = true
        currentIdentity = nil
        authState = .unknown

        // Provider sign-in is a session-mutating operation. Let it settle before
        // clearing Amplify so a late completion cannot recreate a restorable
        // provider session after this sign-out reports success.
        if let pendingSignIn = signInFlight?.task {
            _ = await pendingSignIn.result
        }

        let outcome: CognitoSignOutOutcome
        if let hermeticSignOut {
            outcome = await hermeticSignOut() ? .signedOutLocally : .failedLocally
        } else if let authService {
            outcome = await authService.signOut()
        } else {
            outcome = .signedOutLocally
        }

        guard generation == sessionGeneration else {
            isSigningOut = false
            return false
        }
        isSigningOut = false
        switch outcome {
        case .signedOutLocally:
            try? tokenStore.delete()
            authState = .signedOut
            return true
        case .failedLocally:
            if let previousIdentity {
                currentIdentity = previousIdentity
                authState = .signedIn(previousIdentity)
            } else {
                authState = .signedOut
            }
            return false
        }
    }

    private func clearSignInFlight(_ id: UUID) {
        guard signInFlight?.id == id else { return }
        signInFlight = nil
    }

    private func startRestoration(using service: AuthService) -> Task<Void, Never> {
        guard !isSigningOut else { return Task {} }
        let generation = beginNewGeneration()
        currentIdentity = nil
        authState = .unknown

        let task = Task { [weak self, service] in
            let result: Result<VerifiedSession?, Error>
            do {
                result = .success(try await service.restoreSession())
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            await self?.finishRestoration(result, generation: generation, service: service)
        }
        restorationTask = task
        return task
    }

    private func finishRestoration(
        _ result: Result<VerifiedSession?, Error>,
        generation: UInt64,
        service: AuthService
    ) async {
        guard generation == sessionGeneration else { return }
        restorationTask = nil

        switch result {
        case .success(.some(let candidate)):
            do {
                try commit(candidate, generation: generation)
            } catch {
                await failClosed(generation: generation, using: service)
            }
        case .success(.none), .failure:
            await failClosed(generation: generation, using: service)
        }
    }

    private func commit(_ candidate: VerifiedSession, generation: UInt64) throws {
        guard generation == sessionGeneration else { throw CancellationError() }
        try tokenStore.save(candidate.tokens)
        guard generation == sessionGeneration else { throw CancellationError() }
        currentIdentity = candidate.identity
        authState = .signedIn(candidate.identity)
    }

    private func failClosed(generation: UInt64, using service: AuthService) async {
        guard generation == sessionGeneration, !isSigningOut else { return }
        let closingGeneration = beginNewGeneration()
        isSigningOut = true
        try? tokenStore.delete()
        currentIdentity = nil
        authState = .signedOut
        _ = await service.signOut()
        isSigningOut = false
        guard closingGeneration == sessionGeneration else { return }
        authState = .signedOut
    }

    private func transitionToSignedOut(clearMirror: Bool) {
        _ = beginNewGeneration()
        currentIdentity = nil
        authState = .signedOut
        if clearMirror { try? tokenStore.delete() }
    }

    @discardableResult
    private func beginNewGeneration() -> UInt64 {
        sessionGeneration &+= 1
        restorationTask?.cancel()
        restorationTask = nil
        invalidateRefreshFlight(with: AppError.unauthenticated)
        failAllStepUpWaiters(with: AppError.unauthenticated)
        return sessionGeneration
    }

    // MARK: - Refresh single-flight

    public func performRefresh() async throws -> StoredTokens {
        try await performRefresh(expectedAccountID: nil)
    }

    func performRefresh(expectedAccountID: String?) async throws -> StoredTokens {
        try Task.checkCancellation()
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registerRefreshWaiter(
                    waiterID,
                    expectedAccountID: expectedAccountID,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelRefreshWaiter(waiterID)
            }
        }
    }

    private func registerRefreshWaiter(
        _ waiterID: UUID,
        expectedAccountID: String?,
        continuation: CheckedContinuation<StoredTokens, Error>
    ) {
        guard !Task.isCancelled, let identity = currentIdentity,
              expectedAccountID == nil || identity.subject == expectedAccountID,
              authState != .signedOut, authState != .unknown else {
            continuation.resume(throwing: Task.isCancelled ? CancellationError() : AppError.unauthenticated)
            return
        }

        if var flight = refreshFlight,
           flight.generation == sessionGeneration,
           flight.identity.subject == identity.subject {
            flight.waiters[waiterID] = continuation
            refreshFlight = flight
            return
        }

        guard authService != nil || testRefresher != nil else {
            continuation.resume(throwing: AppError.unauthenticated)
            return
        }

        let flightID = UUID()
        let generation = sessionGeneration
        var flight = RefreshFlight(
            id: flightID,
            generation: generation,
            identity: identity,
            waiters: [waiterID: continuation],
            task: nil
        )

        let service = authService
        let refresher = testRefresher
        let task = Task { [weak self, service, refresher] in
            let result: Result<VerifiedSession, Error>
            do {
                if let service {
                    result = .success(try await service.refreshSession())
                } else if let refresher {
                    let tokens = try await refresher.performRefresh()
                    result = .success(VerifiedSession(identity: identity, tokens: tokens))
                } else {
                    result = .failure(AppError.unauthenticated)
                }
            } catch {
                result = .failure(error)
            }
            await self?.finishRefresh(result, flightID: flightID)
        }
        flight.task = task
        refreshFlight = flight
    }

    private func finishRefresh(
        _ result: Result<VerifiedSession, Error>,
        flightID: UUID
    ) async {
        guard let flight = refreshFlight, flight.id == flightID else { return }
        refreshFlight = nil

        guard flight.generation == sessionGeneration,
              let currentIdentity,
              currentIdentity.subject == flight.identity.subject else {
            resumeRefreshWaiters(flight.waiters, with: .failure(CancellationError()))
            return
        }

        switch result {
        case .success(let candidate):
            guard candidate.identity.subject == flight.identity.subject,
                  candidate.identity.source == flight.identity.source else {
                await failRefreshClosed(
                    flight,
                    error: AppError.unauthenticated
                )
                return
            }
            do {
                try tokenStore.save(candidate.tokens)
                guard flight.generation == sessionGeneration else {
                    resumeRefreshWaiters(flight.waiters, with: .failure(CancellationError()))
                    return
                }
                if case .reconnecting = authState {
                    authState = .signedIn(flight.identity)
                }
                resumeRefreshWaiters(flight.waiters, with: .success(candidate.tokens))
            } catch {
                await failRefreshClosed(flight, error: error)
            }
        case .failure(let error):
            if Self.isUnrecoverableAuthFailure(error) {
                await failRefreshClosed(flight, error: error)
            } else {
                resumeRefreshWaiters(flight.waiters, with: .failure(error))
            }
        }
    }

    private func failRefreshClosed(_ flight: RefreshFlight, error: Error) async {
        if let authService {
            await failClosed(generation: flight.generation, using: authService)
        } else {
            transitionToSignedOut(clearMirror: true)
        }
        resumeRefreshWaiters(flight.waiters, with: .failure(error))
    }

    private static func isUnrecoverableAuthFailure(_ error: Error) -> Bool {
        (error as? AppError)?.isAuthenticationFailure == true
    }

    private func cancelRefreshWaiter(_ waiterID: UUID) {
        guard var flight = refreshFlight,
              let continuation = flight.waiters.removeValue(forKey: waiterID) else {
            return
        }
        continuation.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            refreshFlight = nil
            flight.task?.cancel()
        } else {
            refreshFlight = flight
        }
    }

    private func invalidateRefreshFlight(with error: Error) {
        guard let flight = refreshFlight else { return }
        refreshFlight = nil
        flight.task?.cancel()
        resumeRefreshWaiters(flight.waiters, with: .failure(error))
    }

    private func resumeRefreshWaiters(
        _ waiters: [UUID: CheckedContinuation<StoredTokens, Error>],
        with result: Result<StoredTokens, Error>
    ) {
        for continuation in waiters.values {
            continuation.resume(with: result)
        }
    }

    var refreshWaiterCount: Int { refreshFlight?.waiters.count ?? 0 }

    // MARK: - Step-up

    public func stepUp() async throws {
        try await stepUp(expectedAccountID: nil)
    }

    func stepUp(expectedAccountID: String?) async throws {
        try Task.checkCancellation()
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registerStepUpWaiter(
                    waiterID,
                    expectedAccountID: expectedAccountID,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelStepUpWaiter(waiterID)
            }
        }
    }

    private func registerStepUpWaiter(
        _ waiterID: UUID,
        expectedAccountID: String?,
        continuation: CheckedContinuation<Void, Error>
    ) {
        guard !Task.isCancelled, let identity = currentIdentity,
              expectedAccountID == nil || identity.subject == expectedAccountID else {
            continuation.resume(throwing: Task.isCancelled ? CancellationError() : AppError.unauthenticated)
            return
        }
        switch authState {
        case .signedIn, .reauthRequired:
            stepUpWaiters[waiterID] = StepUpWaiter(
                generation: sessionGeneration,
                identity: identity,
                continuation: continuation
            )
            authState = .reauthRequired
        case .unknown, .signedOut, .reconnecting:
            continuation.resume(throwing: AppError.unauthenticated)
        }
    }

    /// Internal until a real Cognito step-up challenge can supply a
    /// generation-bound proof. The current UI never calls this method.
    func stepUpCompleted() {
        guard case .reauthRequired = authState,
              let identity = currentIdentity,
              !stepUpWaiters.isEmpty,
              stepUpWaiters.values.allSatisfy({
                  $0.generation == sessionGeneration && $0.identity == identity
              }) else {
            return
        }
        let waiters = stepUpWaiters
        stepUpWaiters.removeAll()
        authState = .signedIn(identity)
        for waiter in waiters.values { waiter.continuation.resume() }
    }

    public func stepUpCancelled() async {
        await signOut()
    }

    private func cancelStepUpWaiter(_ waiterID: UUID) {
        guard let waiter = stepUpWaiters.removeValue(forKey: waiterID) else { return }
        waiter.continuation.resume(throwing: CancellationError())
        if stepUpWaiters.isEmpty,
           case .reauthRequired = authState,
           let currentIdentity {
            authState = .signedIn(currentIdentity)
        }
    }

    private func failAllStepUpWaiters(with error: Error) {
        let waiters = stepUpWaiters
        stepUpWaiters.removeAll()
        for waiter in waiters.values { waiter.continuation.resume(throwing: error) }
    }

    var stepUpWaiterCount: Int { stepUpWaiters.count }

    // MARK: - Session recovery and mirror reads

    public func markReconnected() {
        if case .reconnecting = authState, let currentIdentity {
            authState = .signedIn(currentIdentity)
        }
    }

    public func reportSessionError(_ error: AppError) async {
        if case .verifierUnavailable = error, case .signedIn = authState {
            authState = .reconnecting
        }
    }

    /// Applies a persistent session error only to the account whose request
    /// produced it. A stale A request cannot move B into reconnecting state.
    public func reportSessionError(_ error: AppError, forAccountID accountID: String) async {
        guard currentIdentity?.subject == accountID else { return }
        if case .verifierUnavailable = error, case .signedIn = authState {
            authState = .reconnecting
        }
    }

    #if DEBUG
    private func establishHermeticUITestSession() {
        _ = beginNewGeneration()
        currentIdentity = Self.hermeticUITestIdentity
        authState = .signedIn(Self.hermeticUITestIdentity)
    }
    #endif
}

private struct RefreshFlight {
    let id: UUID
    let generation: UInt64
    let identity: SessionIdentity
    var waiters: [UUID: CheckedContinuation<StoredTokens, Error>]
    var task: Task<Void, Never>?
}

private struct SignInFlight {
    let id: UUID
    let generation: UInt64
    let task: Task<VerifiedSession, Error>
}

private struct StepUpWaiter {
    let generation: UInt64
    let identity: SessionIdentity
    let continuation: CheckedContinuation<Void, Error>
}
