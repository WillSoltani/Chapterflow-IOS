import Testing
import Foundation
@testable import AuthKit

// MARK: - Module smoke test

@Suite("AuthKit")
struct AuthKitTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(AuthKit.moduleName == "AuthKit")
    }
}

// MARK: - SessionManager state transitions

@Suite("SessionManager")
@MainActor
struct SessionManagerTests {

    @Test("initialises to .signedIn when id_token is stored")
    func initSignedIn() {
        let store = InMemoryTokenStore(idToken: "id", refreshToken: "ref")
        let session = SessionManager(tokenStore: store)
        #expect(session.authState == .signedIn)
    }

    @Test("initialises to .signedOut when no id_token is stored")
    func initSignedOut() {
        let store = InMemoryTokenStore()
        let session = SessionManager(tokenStore: store)
        #expect(session.authState == .signedOut)
    }

    @Test("didSignIn stores tokens and transitions to .signedIn")
    func didSignInStoresAndTransitions() {
        let store = InMemoryTokenStore()
        let session = SessionManager(tokenStore: store)
        session.didSignIn(idToken: "new-id", refreshToken: "new-ref")
        #expect(session.authState == .signedIn)
        #expect(store.idToken() == "new-id")
        #expect(store.refreshToken() == "new-ref")
    }

    @Test("signOut clears tokens and transitions to .signedOut")
    func signOutClearsAndTransitions() {
        let store = InMemoryTokenStore(idToken: "id", refreshToken: "ref")
        let session = SessionManager(tokenStore: store)
        session.signOut()
        #expect(session.authState == .signedOut)
        #expect(store.idToken() == nil)
        #expect(store.refreshToken() == nil)
    }

    @Test("refresh transitions to .signedOut when no refresh token is stored")
    func refreshSignsOutWithNoRefreshToken() async {
        let store = InMemoryTokenStore(idToken: "id")  // no refresh token
        let session = SessionManager(tokenStore: store, refresher: StubTokenRefresher())
        await #expect(throws: (any Error).self) {
            try await session.refresh()
        }
        #expect(session.authState == .signedOut)
    }

    @Test("refresh updates id_token on success")
    func refreshUpdatesToken() async throws {
        let store = InMemoryTokenStore(idToken: "id", refreshToken: "ref")
        let session = SessionManager(tokenStore: store, refresher: StubTokenRefresher(shouldFail: false))
        try await session.refresh()
        // StubTokenRefresher returns "stub-id-<prefix6>"; "ref".prefix(6) == "ref"
        #expect(store.idToken() == "stub-id-ref")
    }

    @Test("refresh transitions to .signedOut on refresher failure")
    func refreshSignsOutOnFailure() async {
        let store = InMemoryTokenStore(idToken: "id", refreshToken: "ref")
        let session = SessionManager(tokenStore: store, refresher: StubTokenRefresher(shouldFail: true))
        await #expect(throws: (any Error).self) {
            try await session.refresh()
        }
        #expect(session.authState == .signedOut)
    }

    @Test("stepUpCancelled transitions to .signedOut")
    func stepUpCancelledSignsOut() {
        let store = InMemoryTokenStore(idToken: "id", refreshToken: "ref")
        let session = SessionManager(tokenStore: store)
        session.stepUpCancelled()
        #expect(session.authState == .signedOut)
    }

    @Test("stepUpCompleted stores fresh tokens and transitions to .signedIn")
    func stepUpCompletedTransitions() {
        let store = InMemoryTokenStore(idToken: "id", refreshToken: "ref")
        let session = SessionManager(tokenStore: store)
        session.stepUpCompleted(idToken: "fresh-id", refreshToken: "fresh-ref")
        #expect(session.authState == .signedIn)
        #expect(store.idToken() == "fresh-id")
    }

    @Test("markReconnected is a no-op when not in .reconnecting state")
    func markReconnectedNoOp() {
        let store = InMemoryTokenStore(idToken: "id", refreshToken: "ref")
        let session = SessionManager(tokenStore: store)
        session.markReconnected()  // already .signedIn
        #expect(session.authState == .signedIn)
    }

    @Test("currentIdToken returns the stored id_token")
    func currentIdToken() {
        let store = InMemoryTokenStore(idToken: "my-token", refreshToken: "ref")
        let session = SessionManager(tokenStore: store)
        #expect(session.currentIdToken() == "my-token")
    }
}

// MARK: - UserProfile JWT parsing

@Suite("UserProfile")
struct UserProfileTests {

    /// Builds a minimal JWT (header.payload.sig) with the given String claims.
    private func makeJWT(_ claims: [String: String]) throws -> String {
        let header = "eyJhbGciOiJub25lIn0"  // base64url({"alg":"none"})
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
