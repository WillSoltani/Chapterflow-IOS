import AuthKit
import CoreKit
import Foundation
import Networking
import Persistence
import Testing
@testable import AppFeature

@Suite("Session-scoped API client")
@MainActor
struct SessionScopedAPIClientTests {
    @Test("signed-out state cannot start account work")
    func signedOutCannotStartWork() async throws {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let client = SessionScopedAPIClient(
            base: MockAPIClient(),
            context: try makeContext(subject: "account-a"),
            session: session,
            permit: SessionWorkPermit()
        )

        let error = await #expect(throws: AppError.self) {
            let _: TestResponse = try await client.send(testEndpoint)
        }
        guard let error else { return }
        guard case .unauthenticated = error else {
            Issue.record("Expected a closed unauthenticated boundary")
            return
        }
    }

    @Test("active matching account accepts a response")
    func activeAccountAcceptsResponse() async throws {
        let (session, context) = try makeSignedInSession(subject: "account-a")
        let base = MockAPIClient()
        try await base.setStub(TestResponse(value: "accepted"), for: testEndpoint.path)
        let client = SessionScopedAPIClient(
            base: base,
            context: context,
            session: session,
            permit: SessionWorkPermit()
        )

        let response: TestResponse = try await client.send(testEndpoint)
        #expect(response.value == "accepted")
    }

    @Test("late A completion is rejected after its scope is invalidated")
    func lateCompletionCannotEnterNextSession() async throws {
        let (session, context) = try makeSignedInSession(subject: "account-a")
        let base = BlockingAPIClient(response: TestResponse(value: "late-a"))
        let permit = SessionWorkPermit()
        let client = SessionScopedAPIClient(
            base: base,
            context: context,
            session: session,
            permit: permit
        )
        let request = Task<TestResponse, Error> {
            try await client.send(testEndpoint)
        }
        await base.waitUntilStarted()

        permit.invalidate()
        await base.release()

        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
    }

    @Test("work started before quiesce stays stale after resume")
    func resumedScopeRejectsPreQuiesceCompletion() async throws {
        let (session, context) = try makeSignedInSession(subject: "account-a")
        let base = BlockingAPIClient(response: TestResponse(value: "stale"))
        let permit = SessionWorkPermit()
        let client = SessionScopedAPIClient(
            base: base,
            context: context,
            session: session,
            permit: permit
        )
        let request = Task<TestResponse, Error> {
            try await client.send(testEndpoint)
        }
        await base.waitUntilStarted()

        permit.quiesce()
        permit.resume()
        await base.release()

        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
    }

    @Test("quiesce during final account check rejects completion")
    func quiesceDuringFinalAccountCheck() async throws {
        let (session, context) = try makeSignedInSession(subject: "account-a")
        let base = MockAPIClient()
        try await base.setStub(TestResponse(value: "must-not-publish"), for: testEndpoint.path)
        let permit = SessionWorkPermit()
        let gate = BlockingSecondAccountCheck()
        let client = SessionScopedAPIClient(
            base: base,
            context: context,
            session: session,
            permit: permit,
            accountCheckHook: { await gate.check() }
        )
        let request = Task<TestResponse, Error> {
            try await client.send(testEndpoint)
        }

        await gate.waitUntilBlocked()
        permit.quiesce()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
    }

    @Test("A mutation cannot acquire B token after wrapper authorization")
    func mutationCannotCrossTokenAcquisitionBoundary() async throws {
        let identityA = try makeIdentity(subject: "account-a")
        let identityB = try makeIdentity(subject: "account-b")
        let session = SessionManager(
            tokenStore: InMemoryTokenStore(tokens: makeTokens(subject: identityA.subject)),
            refresher: StubTokenRefresher(),
            hermeticIdentity: identityA
        )
        let context = try makeContext(identity: identityA)
        let permit = SessionWorkPermit()
        let boundTokenProvider = AccountBoundSessionTokenProvider(
            context: context,
            session: session,
            permit: permit
        )
        let base = DelayedTokenAcquiringAPIClient(
            tokenProvider: boundTokenProvider,
            response: TestResponse(value: "must-not-send")
        )
        let client = SessionScopedAPIClient(
            base: base,
            context: context,
            session: session,
            permit: permit
        )
        let request = Task<TestResponse, Error> {
            try await client.send(Endpoint(method: .post, path: "/account-mutation"))
        }
        await base.waitUntilTokenAcquisitionCanBegin()

        try session.establishHermeticSession(
            identity: identityB,
            tokens: makeTokens(subject: identityB.subject)
        )
        await base.releaseTokenAcquisition()

        let error = await #expect(throws: AppError.self) {
            _ = try await request.value
        }
        guard let error else { return }
        guard case .unauthenticated = error else {
            Issue.record("Expected the account-bound provider to fail closed")
            return
        }
        #expect(await base.didSendRequest == false)
    }

    private var testEndpoint: Endpoint {
        Endpoint(method: .get, path: "/account-test", requiresAuth: true)
    }

    private func makeSignedInSession(
        subject: String
    ) throws -> (SessionManager, AccountContext) {
        let identity = try #require(SessionIdentity(
            subject: subject,
            username: nil,
            email: nil,
            source: .cognitoUserPool
        ))
        let session = SessionManager(
            tokenStore: InMemoryTokenStore(),
            refresher: StubTokenRefresher(),
            hermeticIdentity: identity
        )
        return (session, try makeContext(identity: identity))
    }

    private func makeContext(subject: String) throws -> AccountContext {
        let identity = try makeIdentity(subject: subject)
        return try makeContext(identity: identity)
    }

    private func makeIdentity(subject: String) throws -> SessionIdentity {
        try #require(SessionIdentity(
            subject: subject,
            username: nil,
            email: nil,
            source: .cognitoUserPool
        ))
    }

    private func makeTokens(subject: String) -> StoredTokens {
        let payload = Data(
            "{\"sub\":\"\(subject)\",\"exp\":9999999999}".utf8
        )
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
        return StoredTokens(
            idToken: "eyJhbGciOiJub25lIn0.\(payload).signature",
            accessToken: "access-\(subject)",
            refreshToken: "refresh-\(subject)",
            expiresAt: Date().addingTimeInterval(3_600)
        )
    }

    private func makeContext(identity: SessionIdentity) throws -> AccountContext {
        let config = AppConfig(
            apiBaseURL: "https://api.chapterflow.test",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_ChapterFlowTests",
            cognitoClientID: "chapterflowtestsclient12345",
            cognitoDomain: "auth.chapterflow.test"
        )
        guard case let .valid(validated) = config.validate() else {
            throw TestSetupError.invalidConfiguration
        }
        return AccountContext(identity: identity, config: validated)
    }

    private enum TestSetupError: Error {
        case invalidConfiguration
    }
}

private actor BlockingSecondAccountCheck {
    private var callCount = 0
    private var isBlocked = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func check() async {
        callCount += 1
        guard callCount == 2 else { return }
        isBlocked = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
    }

    func waitUntilBlocked() async {
        guard !isBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private struct TestResponse: Codable, Sendable, Equatable {
    let value: String
}

private actor BlockingAPIClient: APIClientProtocol {
    private let data: Data
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    init<Response: Encodable & Sendable>(response: Response) {
        data = try! JSONCoding.encoder.encode(response)
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        _ = endpoint
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor DelayedTokenAcquiringAPIClient: APIClientProtocol {
    private let tokenProvider: any TokenProviding
    private let data: Data
    private var didReachTokenBoundary = false
    private var tokenBoundaryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private(set) var didSendRequest = false

    init<Response: Encodable & Sendable>(
        tokenProvider: any TokenProviding,
        response: Response
    ) {
        self.tokenProvider = tokenProvider
        data = try! JSONCoding.encoder.encode(response)
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        _ = endpoint
        didReachTokenBoundary = true
        let waiters = tokenBoundaryWaiters
        tokenBoundaryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        _ = try await tokenProvider.validToken()
        didSendRequest = true
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    func waitUntilTokenAcquisitionCanBegin() async {
        guard !didReachTokenBoundary else { return }
        await withCheckedContinuation { continuation in
            tokenBoundaryWaiters.append(continuation)
        }
    }

    func releaseTokenAcquisition() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
