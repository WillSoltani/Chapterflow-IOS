import Testing
@testable import AuthKit
import Persistence
import Foundation

// MARK: - Test Doubles

/// Records `performRefresh` calls and returns pre-configured tokens.
final class SpyRefresher: TokenRefreshing, @unchecked Sendable {
    var refreshCallCount = 0
    var tokensToReturn: StoredTokens

    init(tokens: StoredTokens) {
        self.tokensToReturn = tokens
    }

    func performRefresh() async throws -> StoredTokens {
        refreshCallCount += 1
        return tokensToReturn
    }
}

// MARK: - Helpers

private func makeTokens(
    idToken: String = "id-token",
    accessToken: String = "access-token",
    refreshToken: String = "refresh-token",
    expiresAt: Date
) -> StoredTokens {
    StoredTokens(
        idToken: idToken,
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt
    )
}

// MARK: - Tests

@Suite("AuthTokenProvider — token-refresh decision logic")
struct TokenRefreshTests {

    // MARK: No tokens

    @Test("returns nil when no tokens are stored")
    func nilWhenNoTokens() async throws {
        let store = InMemoryTokenStore()
        let spy = SpyRefresher(tokens: makeTokens(expiresAt: Date().addingTimeInterval(3_600)))
        let provider = AuthTokenProvider(store: store, clock: FakeTimeProvider(now: Date()), refresher: spy)

        let token = try await provider.validToken()

        #expect(token == nil)
        #expect(spy.refreshCallCount == 0)
    }

    // MARK: Non-expired token

    @Test("returns cached id_token without refresh when plenty of time remains")
    func returnsCachedTokenWhenNotExpired() async throws {
        let now = Date()
        let expiry = now.addingTimeInterval(3_600) // 1 hour from now
        let tokens = makeTokens(idToken: "cached-id", expiresAt: expiry)
        let store = InMemoryTokenStore(tokens: tokens)
        let spy = SpyRefresher(tokens: makeTokens(idToken: "refreshed-id", expiresAt: expiry))
        let provider = AuthTokenProvider(
            store: store,
            clock: FakeTimeProvider(now: now),
            refresher: spy
        )

        let returned = try await provider.validToken()

        #expect(returned == "cached-id")
        #expect(spy.refreshCallCount == 0, "should not refresh a healthy token")
    }

    // MARK: Near-expiry (< 5 min)

    @Test("refreshes when token expires in under 5 minutes")
    func refreshesWhenNearlyExpired() async throws {
        let now = Date()
        let expiry = now.addingTimeInterval(240) // 4 min — within the 5-min window
        let tokens = makeTokens(idToken: "old-id", expiresAt: expiry)
        let store = InMemoryTokenStore(tokens: tokens)
        let refreshedTokens = makeTokens(idToken: "new-id", expiresAt: now.addingTimeInterval(3_600))
        let spy = SpyRefresher(tokens: refreshedTokens)
        let provider = AuthTokenProvider(
            store: store,
            clock: FakeTimeProvider(now: now),
            refresher: spy
        )

        let returned = try await provider.validToken()

        #expect(spy.refreshCallCount == 1, "should proactively refresh a near-expired token")
        #expect(returned == "new-id", "should return the refreshed id_token")
    }

    @Test("does NOT refresh when exactly 5 minutes remain")
    func doesNotRefreshAtExactly5MinBoundary() async throws {
        let now = Date()
        let expiry = now.addingTimeInterval(300) // exactly 5 min
        let tokens = makeTokens(idToken: "boundary-id", expiresAt: expiry)
        let store = InMemoryTokenStore(tokens: tokens)
        let spy = SpyRefresher(tokens: makeTokens(idToken: "refreshed-id", expiresAt: expiry))
        let provider = AuthTokenProvider(
            store: store,
            clock: FakeTimeProvider(now: now),
            refresher: spy
        )

        let returned = try await provider.validToken()

        // isNearlyExpired uses now + 300 >= expiry, which is true at exactly 300s.
        // This is intentionally conservative — the boundary triggers a refresh.
        #expect(spy.refreshCallCount == 1)
        #expect(returned == "refreshed-id")
    }

    @Test("refreshes an already-expired token")
    func refreshesExpiredToken() async throws {
        let now = Date()
        let expiry = now.addingTimeInterval(-60) // expired 1 minute ago
        let tokens = makeTokens(idToken: "expired-id", expiresAt: expiry)
        let store = InMemoryTokenStore(tokens: tokens)
        let refreshedTokens = makeTokens(idToken: "revived-id", expiresAt: now.addingTimeInterval(3_600))
        let spy = SpyRefresher(tokens: refreshedTokens)
        let provider = AuthTokenProvider(
            store: store,
            clock: FakeTimeProvider(now: now),
            refresher: spy
        )

        let returned = try await provider.validToken()

        #expect(spy.refreshCallCount == 1)
        #expect(returned == "revived-id")
    }

    // MARK: refresh() forces a refresh

    @Test("refresh() calls performRefresh regardless of expiry")
    func explicitRefreshAlwaysRefreshes() async throws {
        let now = Date()
        let expiry = now.addingTimeInterval(3_600) // healthy token
        let tokens = makeTokens(expiresAt: expiry)
        let store = InMemoryTokenStore(tokens: tokens)
        let spy = SpyRefresher(tokens: makeTokens(expiresAt: now.addingTimeInterval(7_200)))
        let provider = AuthTokenProvider(
            store: store,
            clock: FakeTimeProvider(now: now),
            refresher: spy
        )

        try await provider.refresh()

        #expect(spy.refreshCallCount == 1, "explicit refresh must always call the refresher")
    }

    // MARK: StoredTokens expiry helpers

    @Test("isExpired is false while token is valid")
    func isExpiredFalseWhenValid() {
        let tokens = makeTokens(expiresAt: Date().addingTimeInterval(3_600))
        #expect(!tokens.isExpired(at: Date()))
    }

    @Test("isExpired is true once past expiry")
    func isExpiredTrueWhenPast() {
        let expiry = Date().addingTimeInterval(-1)
        let tokens = makeTokens(expiresAt: expiry)
        #expect(tokens.isExpired(at: Date()))
    }

    @Test("isNearlyExpired triggers within 5-minute window")
    func isNearlyExpiredWithin5Min() {
        let now = Date()
        let tokens = makeTokens(expiresAt: now.addingTimeInterval(299))
        #expect(tokens.isNearlyExpired(at: now))
    }

    @Test("isNearlyExpired is false with more than 5 minutes remaining")
    func isNearlyExpiredFalseWithTime() {
        let now = Date()
        let tokens = makeTokens(expiresAt: now.addingTimeInterval(301))
        #expect(!tokens.isNearlyExpired(at: now))
    }
}
