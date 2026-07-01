import Testing
import Foundation
@testable import AuthKit
import Persistence

@Suite("AuthTokenProvider")
struct TokenRefreshTests {

    private func freshTokens(expiresIn: TimeInterval = 3_600) -> StoredTokens {
        StoredTokens(
            idToken: "cached-id",
            accessToken: "cached-access",
            refreshToken: "cached-refresh",
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    @Test("returns nil when the store is empty")
    func returnsNilWhenEmpty() async throws {
        let store = InMemoryTokenStore()
        let provider = AuthTokenProvider(store: store, refresher: StubTokenRefresher())
        let token = try await provider.validToken()
        #expect(token == nil)
    }

    @Test("returns cached id_token when not near expiry")
    func returnsCachedToken() async throws {
        let tokens = freshTokens(expiresIn: 3_600)
        let store = InMemoryTokenStore(tokens: tokens)
        let provider = AuthTokenProvider(
            store: store,
            clock: FakeTimeProvider(now: Date()),
            refresher: StubTokenRefresher()
        )
        let token = try await provider.validToken()
        #expect(token == "cached-id")
    }

    @Test("triggers refresh when token is within 5 minutes of expiry")
    func triggersRefreshWhenNearlyExpired() async throws {
        let expiresAt = Date().addingTimeInterval(60)
        let tokens = StoredTokens(
            idToken: "old-id",
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: expiresAt
        )
        let store = InMemoryTokenStore(tokens: tokens)
        // Clock is 290 seconds before expiry — adding 300 exceeds expiresAt → nearlyExpired.
        let fakeNow = expiresAt.addingTimeInterval(-290)
        let provider = AuthTokenProvider(
            store: store,
            clock: FakeTimeProvider(now: fakeNow),
            refresher: StubTokenRefresher(shouldFail: false)
        )
        let token = try await provider.validToken()
        #expect(token == "stub-id-token")
    }

    @Test("returns cached token when just outside the 5-minute window")
    func noRefreshOutsideWindow() async throws {
        let expiresAt = Date().addingTimeInterval(3_600)
        let tokens = StoredTokens(
            idToken: "cached-id",
            accessToken: "cached-access",
            refreshToken: "cached-refresh",
            expiresAt: expiresAt
        )
        let store = InMemoryTokenStore(tokens: tokens)
        // 301 seconds before expiry — adding 300 does NOT reach expiresAt.
        let fakeNow = expiresAt.addingTimeInterval(-301)
        let provider = AuthTokenProvider(
            store: store,
            clock: FakeTimeProvider(now: fakeNow),
            refresher: StubTokenRefresher()
        )
        let token = try await provider.validToken()
        #expect(token == "cached-id")
    }

    @Test("refresh() propagates refresher errors")
    func refreshPropagatesError() async {
        let store = InMemoryTokenStore(tokens: freshTokens())
        let provider = AuthTokenProvider(
            store: store,
            refresher: StubTokenRefresher(shouldFail: true)
        )
        await #expect(throws: (any Error).self) {
            try await provider.refresh()
        }
    }
}
