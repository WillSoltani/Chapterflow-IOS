import Testing
import Foundation
@testable import AuthKit
import Persistence

// MARK: - Module smoke test

@Suite("AuthKit")
struct AuthKitModuleTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(AuthKit.moduleName == "AuthKit")
    }
}

// MARK: - SessionManager state transitions

private func makeTokens(expiresIn: TimeInterval = 3_600) -> StoredTokens {
    let payload = Data(
        #"{"sub":"test-subject","exp":9999999999,"name":"Test Reader"}"#.utf8
    )
    .base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
    return StoredTokens(
        idToken: "eyJhbGciOiJub25lIn0.\(payload).signature",
        accessToken: "test-access-token",
        refreshToken: "test-refresh-token",
        expiresAt: Date().addingTimeInterval(expiresIn)
    )
}

private let testIdentity: SessionIdentity = {
    guard let identity = SessionIdentity(
        subject: "test-subject",
        username: "test",
        email: nil,
        source: .cognitoUserPool
    ) else {
        preconditionFailure("Invalid fixed test identity")
    }
    return identity
}()

@MainActor
private func makeAuthenticatedSession(
    store: InMemoryTokenStore,
    refresher: any TokenRefreshing = StubTokenRefresher()
) -> SessionManager {
    SessionManager(tokenStore: store, refresher: refresher, testIdentity: testIdentity)
}

private extension AuthState {
    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

@Suite("SessionManager")
@MainActor
struct SessionManagerTests {

    @Test("stored tokens alone never establish authentication")
    func storedTokensAloneStaySignedOut() {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store)
        #expect(session.authState == .signedOut)
    }

    @Test("initialises to .signedOut when no tokens are stored")
    func initSignedOut() {
        let store = InMemoryTokenStore()
        let session = SessionManager(tokenStore: store)
        #expect(session.authState == .signedOut)
    }

    @Test("initialises to .signedOut when stored tokens are expired")
    func initExpired() {
        let store = InMemoryTokenStore(tokens: makeTokens(expiresIn: -1))
        let session = SessionManager(tokenStore: store)
        #expect(session.authState == .signedOut)
    }

    @Test("signOut clears tokens and transitions to .signedOut")
    func signOutClearsTokens() async throws {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = makeAuthenticatedSession(store: store)
        await session.signOut()
        #expect(session.authState == .signedOut)
        #expect(try store.load() == nil)
    }

    @Test("refresh updates stored tokens on success")
    func refreshUpdatesTokens() async throws {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = makeAuthenticatedSession(
            store: store,
            refresher: StubTokenRefresher(shouldFail: false)
        )
        try await session.refresh()
        #expect(try store.load()?.idToken == StubTokenRefresher.fixedIDToken)
    }

    @Test("refresh transitions to .signedOut when refresher fails")
    func refreshSignsOutOnFailure() async {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = makeAuthenticatedSession(
            store: store,
            refresher: StubTokenRefresher(shouldFail: true)
        )
        await #expect(throws: (any Error).self) {
            try await session.refresh()
        }
        #expect(session.authState == .signedOut)
    }

    @Test("currentIdToken returns the stored id_token")
    func currentIdToken() {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = makeAuthenticatedSession(store: store)
        #expect(session.currentIdToken() == makeTokens().idToken)
    }

    @Test("stepUpCancelled transitions to .signedOut")
    func stepUpCancelledSignsOut() async {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = makeAuthenticatedSession(store: store)
        await session.stepUpCancelled()
        #expect(session.authState == .signedOut)
    }

    @Test("step-up completion cannot synthesize identity")
    func stepUpCannotCreateIdentity() {
        let session = SessionManager(tokenStore: InMemoryTokenStore())

        session.stepUpCompleted()

        #expect(session.authState == .signedOut)
    }

    @Test("markReconnected is a no-op when not in .reconnecting state")
    func markReconnectedRestoresIdentity() async {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = makeAuthenticatedSession(store: store)
        await session.reportSessionError(.verifierUnavailable)
        session.markReconnected()
        #expect(session.authState.isSignedIn)
    }

    // MARK: Mirror consistency — single write path

    /// Verifies that the TokenStore mirror stays consistent with auth events:
    /// - After refresh, the mirror holds the new token.
    /// - After sign-out, the mirror is empty.
    /// This ensures the single-writer invariant holds: only the session authority
    /// ever writes to the store, and sign-out wipes it completely.
    @Test("mirror consistency: refresh updates store, sign-out wipes it")
    func mirrorConsistency() async throws {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = makeAuthenticatedSession(
            store: store,
            refresher: StubTokenRefresher(shouldFail: false)
        )

        // Initially the store has the pre-seeded tokens.
        #expect(try store.load() != nil)

        // Refresh writes the stub tokens through the single write path.
        try await session.refresh()
        let afterRefresh = try store.load()
        #expect(
            afterRefresh?.idToken == StubTokenRefresher.fixedIDToken,
            "mirror must reflect refreshed token"
        )

        // Sign-out must clear the mirror completely.
        await session.signOut()
        #expect(try store.load() == nil, "sign-out must wipe the token mirror")
        #expect(session.authState == .signedOut)
    }

    @Test("mirror consistency: fresh store means signedOut state")
    func mirrorEmptyIsSignedOut() throws {
        let store = InMemoryTokenStore()
        let session = SessionManager(tokenStore: store)
        #expect(session.authState == .signedOut)
        #expect(try store.load() == nil)
    }

    // MARK: validToken() — proactive refresh (RF: transparent Amplify refresh)

    @Test("validToken() returns the cached id_token when it is fresh")
    func validTokenReturnsCachedWhenFresh() async throws {
        let store = InMemoryTokenStore(tokens: makeTokens(expiresIn: 3_600))
        let session = makeAuthenticatedSession(
            store: store,
            refresher: StubTokenRefresher(shouldFail: true)
        )
        let token = try await session.validToken()
        // Fresh token — no refresh triggered despite a failing refresher.
        #expect(token == makeTokens().idToken)
    }

    @Test("validToken() proactively refreshes when token is near-expiry (<5 min)")
    func validTokenProactivelyRefreshesNearExpiry() async throws {
        // 60 seconds left — well inside the 5-minute window.
        let store = InMemoryTokenStore(tokens: makeTokens(expiresIn: 60))
        let session = makeAuthenticatedSession(store: store)
        let token = try await session.validToken()
        #expect(token == StubTokenRefresher.fixedIDToken, "should return the refreshed token")
        #expect(
            try store.load()?.idToken == StubTokenRefresher.fixedIDToken,
            "store must hold the new token"
        )
    }

    @Test("validToken() proactively refreshes an already-expired token")
    func validTokenRefreshesExpiredToken() async throws {
        let store = InMemoryTokenStore(tokens: makeTokens(expiresIn: -60))
        let session = makeAuthenticatedSession(store: store)
        let token = try await session.validToken()
        #expect(token == StubTokenRefresher.fixedIDToken)
    }

    @Test("validToken() propagates proactive refresh failure without trusting stale mirror")
    func validTokenPropagatesRefreshFailure() async {
        let store = InMemoryTokenStore(tokens: makeTokens(expiresIn: 60))
        let session = makeAuthenticatedSession(
            store: store,
            refresher: StubTokenRefresher(shouldFail: true)
        )
        await #expect(throws: (any Error).self) {
            try await session.validToken()
        }
    }

    @Test("validToken() returns nil when no tokens are stored (unauthenticated)")
    func validTokenNilWhenEmpty() async throws {
        let store = InMemoryTokenStore()
        let session = SessionManager(tokenStore: store)
        let token = try await session.validToken()
        #expect(token == nil)
    }

    @Test("validToken() ignores a mirror without an authoritative session")
    func validTokenIgnoresMirrorWithoutSession() async throws {
        let session = SessionManager(
            tokenStore: InMemoryTokenStore(tokens: makeTokens())
        )

        #expect(try await session.validToken() == nil)
    }

    // MARK: Sign-out keychain cleanup (RF4)

    @Test("signOut clears TokenStore and authState — no credentials left behind")
    func signOutLeavesEmptyKeychain() async throws {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = makeAuthenticatedSession(store: store)
        #expect(try store.load() != nil)
        await session.signOut()
        #expect(try store.load() == nil, "TokenStore must be empty after sign-out")
        #expect(session.authState == .signedOut)
    }
}

// MARK: - UserProfile JWT parsing

@Suite("UserProfile")
struct UserProfileTests {

    private func makeJWT(_ claims: [String: String]) throws -> String {
        let header = "eyJhbGciOiJub25lIn0"
        let data = try JSONSerialization.data(withJSONObject: claims)
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload).fakesig"
    }

    @Test("extracts name claim as displayName")
    func extractsNameClaim() throws {
        let jwt = try makeJWT(["sub": "abc", "email": "x@y.com", "name": "Alice Smith"])
        let profile = try #require(UserProfile.from(idToken: jwt))
        #expect(profile.displayName == "Alice Smith")
        #expect(profile.email == "x@y.com")
    }

    @Test("combines given_name and family_name when name is absent")
    func combinesGivenFamily() throws {
        let jwt = try makeJWT(["sub": "abc", "given_name": "Bob", "family_name": "Jones"])
        let profile = try #require(UserProfile.from(idToken: jwt))
        #expect(profile.displayName == "Bob Jones")
    }

    @Test("falls back to email prefix when no name claims are present")
    func emailPrefixFallback() throws {
        let jwt = try makeJWT(["sub": "abc", "email": "charlie@example.com"])
        let profile = try #require(UserProfile.from(idToken: jwt))
        #expect(profile.displayName == "charlie")
    }

    @Test("falls back to Reader when only sub is present")
    func readerFallback() throws {
        let jwt = try makeJWT(["sub": "abc"])
        let profile = try #require(UserProfile.from(idToken: jwt))
        #expect(profile.displayName == "Reader")
    }

    @Test("returns nil for a single-segment token")
    func nilForSingleSegment() {
        #expect(UserProfile.from(idToken: "notajwt") == nil)
    }

    @Test("prefers name over given_name + family_name")
    func namePreferredOverGiven() throws {
        let jwt = try makeJWT([
            "sub": "abc",
            "name": "Full Name",
            "given_name": "Given",
            "family_name": "Family",
        ])
        let profile = try #require(UserProfile.from(idToken: jwt))
        #expect(profile.displayName == "Full Name")
    }
}
