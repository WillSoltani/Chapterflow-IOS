import CoreKit
import Foundation
import Persistence
import Testing
@testable import AuthKit

let subjectA = "cognito-subject-a"
let subjectB = "cognito-subject-b"

enum TestExpiryClaim: Sendable {
    case valid
    case missing
    case text
}

func makeIDToken(
    subject: String?,
    expiresIn: TimeInterval = 3_600,
    expiryClaim: TestExpiryClaim = .valid
) -> String {
    let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8)
        .base64URLEncodedString()
    var claims: [String: Any] = ["name": "Reader"]
    switch expiryClaim {
    case .valid:
        claims["exp"] = Date().addingTimeInterval(expiresIn).timeIntervalSince1970
    case .missing:
        break
    case .text:
        claims["exp"] = "later"
    }
    if let subject { claims["sub"] = subject }
    let payload = (try? JSONSerialization.data(withJSONObject: claims))?
        .base64URLEncodedString() ?? ""
    return "\(header).\(payload).signature"
}

func makeSessionTokens(
    subject: String? = subjectA,
    expiresIn: TimeInterval = 3_600,
    marker: String = "a",
    expiryClaim: TestExpiryClaim = .valid
) -> StoredTokens {
    StoredTokens(
        idToken: makeIDToken(
            subject: subject,
            expiresIn: expiresIn,
            expiryClaim: expiryClaim
        ),
        accessToken: "access-\(marker)",
        refreshToken: "refresh-\(marker)",
        expiresAt: Date().addingTimeInterval(expiresIn)
    )
}

func makeIdentity(_ subject: String = subjectA) throws -> SessionIdentity {
    try #require(SessionIdentity(
        subject: subject,
        username: "reader",
        email: nil,
        source: .cognitoUserPool
    ))
}

func makeAuthConfig() -> AppConfig {
    AppConfig(
        apiBaseURL: "https://api.chapterflow.test",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "us-east-1_test",
        cognitoClientID: "test-client"
    )
}

@MainActor
func waitForRefreshWaiters(_ count: Int, on session: SessionManager) async {
    for _ in 0..<200 {
        if session.refreshWaiterCount >= count { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for \(count) refresh waiter(s)")
}

@MainActor
func waitForStepUpWaiters(_ count: Int, on session: SessionManager) async {
    for _ in 0..<200 {
        if session.stepUpWaiterCount >= count { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for \(count) step-up waiter(s)")
}

actor ScriptedCognitoSessionClient: CognitoSessionClient {
    private var session: CognitoSessionSnapshot
    private let signInSession: CognitoSessionSnapshot?
    private var user: CognitoUserSnapshot
    private var signInOutcome: CognitoSignInOutcome
    private var signOutOutcome: CognitoSignOutOutcome
    private var shouldSuspendSignIn: Bool
    private var shouldSuspendRefresh: Bool
    private var signInContinuations: [CheckedContinuation<CognitoSignInOutcome, Error>] = []
    private var signInStartWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var refreshContinuations: [CheckedContinuation<CognitoSessionSnapshot, Error>] = []
    private var refreshStartWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    private(set) var signInCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var fetchCallCount = 0
    private(set) var currentUserCallCount = 0
    private(set) var signOutCallCount = 0

    var totalSessionCallCount: Int {
        signInCallCount + fetchCallCount + currentUserCallCount + signOutCallCount
    }

    init(
        session: CognitoSessionSnapshot,
        user: CognitoUserSnapshot,
        suspendSignIn: Bool = false,
        signInSession: CognitoSessionSnapshot? = nil,
        suspendRefresh: Bool = false,
        signInOutcome: CognitoSignInOutcome = .signedIn,
        signOutOutcome: CognitoSignOutOutcome = .signedOutLocally
    ) {
        self.session = session
        self.signInSession = signInSession
        self.user = user
        self.shouldSuspendSignIn = suspendSignIn
        self.shouldSuspendRefresh = suspendRefresh
        self.signInOutcome = signInOutcome
        self.signOutOutcome = signOutOutcome
    }

    func signIn(username: String, password: String) async throws -> CognitoSignInOutcome {
        signInCallCount += 1
        let ready = signInStartWaiters.filter { $0.0 <= signInCallCount }
        signInStartWaiters.removeAll { $0.0 <= signInCallCount }
        ready.forEach { $0.1.resume() }
        guard shouldSuspendSignIn else { return signInOutcome }
        return try await withCheckedThrowingContinuation { continuation in
            signInContinuations.append(continuation)
        }
    }

    func fetchSession(forceRefresh: Bool) async throws -> CognitoSessionSnapshot {
        fetchCallCount += 1
        guard forceRefresh else { return session }
        refreshCallCount += 1
        let ready = refreshStartWaiters.filter { $0.0 <= refreshCallCount }
        refreshStartWaiters.removeAll { $0.0 <= refreshCallCount }
        ready.forEach { $0.1.resume() }
        guard shouldSuspendRefresh else { return session }
        return try await withCheckedThrowingContinuation { continuation in
            refreshContinuations.append(continuation)
        }
    }

    func currentUser() async throws -> CognitoUserSnapshot {
        currentUserCallCount += 1
        return user
    }

    func signOut() async -> CognitoSignOutOutcome {
        signOutCallCount += 1
        if signOutOutcome == .signedOutLocally {
            session = CognitoSessionSnapshot(isSignedIn: false, tokens: nil)
        }
        return signOutOutcome
    }

    func setSession(_ session: CognitoSessionSnapshot) {
        self.session = session
    }

    func setUser(_ user: CognitoUserSnapshot) {
        self.user = user
    }

    func waitForSignInCallCount(_ count: Int) async {
        guard signInCallCount < count else { return }
        await withCheckedContinuation { continuation in
            signInStartWaiters.append((count, continuation))
        }
    }

    func releaseSignIn(with result: Result<CognitoSignInOutcome, Error>) {
        shouldSuspendSignIn = false
        if case .success(.signedIn) = result, let signInSession {
            session = signInSession
        }
        let continuations = signInContinuations
        signInContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(with: result)
        }
    }

    func waitForRefreshCallCount(_ count: Int) async {
        guard refreshCallCount < count else { return }
        await withCheckedContinuation { continuation in
            refreshStartWaiters.append((count, continuation))
        }
    }

    func releaseRefresh(with result: Result<CognitoSessionSnapshot, Error>) {
        shouldSuspendRefresh = false
        let continuations = refreshContinuations
        refreshContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(with: result)
        }
    }
}

final class ThrowingLoadTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: StoredTokens?
    private var loadFailures: Int

    init(tokens: StoredTokens?, loadFailures: Int) {
        self.tokens = tokens
        self.loadFailures = loadFailures
    }

    func save(_ tokens: StoredTokens) throws {
        lock.withLock { self.tokens = tokens }
    }

    func load() throws -> StoredTokens? {
        try lock.withLock {
            if loadFailures > 0 {
                loadFailures -= 1
                throw PersistenceError.invalidTokenData
            }
            return tokens
        }
    }

    func delete() throws {
        lock.withLock { tokens = nil }
    }

    var snapshot: StoredTokens? {
        lock.withLock { tokens }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
