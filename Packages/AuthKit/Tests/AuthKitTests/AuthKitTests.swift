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
    StoredTokens(
        idToken: "test-id-token",
        accessToken: "test-access-token",
        refreshToken: "test-refresh-token",
        expiresAt: Date().addingTimeInterval(expiresIn)
    )
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

    @Test("initialises to .signedIn when valid tokens are stored")
    func initSignedIn() {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store)
        #expect(session.authState.isSignedIn)
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
    func signOutClearsTokens() async {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store)
        await session.signOut()
        #expect(session.authState == .signedOut)
        #expect(store.load() == nil)
    }

    @Test("refresh updates stored tokens on success")
    func refreshUpdatesTokens() async throws {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store, refresher: StubTokenRefresher(shouldFail: false))
        try await session.refresh()
        #expect(store.load()?.idToken == "stub-id-token")
    }

    @Test("refresh transitions to .signedOut when refresher fails")
    func refreshSignsOutOnFailure() async {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store, refresher: StubTokenRefresher(shouldFail: true))
        await #expect(throws: (any Error).self) {
            try await session.refresh()
        }
        #expect(session.authState == .signedOut)
    }

    @Test("currentIdToken returns the stored id_token")
    func currentIdToken() {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store)
        #expect(session.currentIdToken() == "test-id-token")
    }

    @Test("stepUpCancelled transitions to .signedOut")
    func stepUpCancelledSignsOut() async {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store)
        session.stepUpCancelled()
        // stepUpCancelled calls Task { await signOut() }, give it a moment
        try? await Task.sleep(for: .milliseconds(50))
        #expect(session.authState == .signedOut)
    }

    @Test("markReconnected is a no-op when not in .reconnecting state")
    func markReconnectedNoOp() {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store)
        session.markReconnected()
        #expect(session.authState.isSignedIn)
    }

    // MARK: Mirror consistency — single write path

    /// Verifies that the TokenStore mirror stays consistent with auth events:
    /// - After refresh, the mirror holds the new token.
    /// - After sign-out, the mirror is empty.
    /// This ensures the single-writer invariant holds: only the auth service path
    /// ever writes to the store, and sign-out wipes it completely.
    @Test("mirror consistency: refresh updates store, sign-out wipes it")
    func mirrorConsistency() async throws {
        let store = InMemoryTokenStore(tokens: makeTokens())
        let session = SessionManager(tokenStore: store, refresher: StubTokenRefresher(shouldFail: false))

        // Initially the store has the pre-seeded tokens.
        #expect(store.load() != nil)

        // Refresh writes the stub tokens through the single write path.
        try await session.refresh()
        let afterRefresh = store.load()
        #expect(afterRefresh?.idToken == "stub-id-token", "mirror must reflect refreshed token")

        // Sign-out must clear the mirror completely.
        await session.signOut()
        #expect(store.load() == nil, "sign-out must wipe the token mirror")
        #expect(session.authState == .signedOut)
    }

    @Test("mirror consistency: fresh store means signedOut state")
    func mirrorEmptyIsSignedOut() {
        let store = InMemoryTokenStore()
        let session = SessionManager(tokenStore: store)
        #expect(session.authState == .signedOut)
        #expect(store.load() == nil)
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
