import Foundation
import Networking
import Persistence

// MARK: - TimeProvider

/// Abstracts the current time so token-expiry decisions are unit-testable.
public protocol TimeProvider: Sendable {
    var now: Date { get }
}

public struct SystemTimeProvider: TimeProvider, Sendable {
    public var now: Date { Date() }
    public init() {}
}

/// A fixed-time provider for deterministic tests.
public struct FakeTimeProvider: TimeProvider, Sendable {
    public let now: Date
    public init(now: Date) { self.now = now }
}

// MARK: - AuthTokenProvider

/// `TokenProviding` implementation wired into `APIClient`.
///
/// Decision logic:
/// 1. No tokens in store → return `nil` (unauthenticated).
/// 2. Tokens are near-expiry (< 5 min) or expired → force-refresh, then return new id_token.
/// 3. Otherwise → return the cached id_token immediately.
///
/// The `TimeProvider` and `TokenStoring` dependencies are injected so the
/// refresh-decision logic can be exercised with a fake clock in unit tests.
public actor AuthTokenProvider: TokenProviding {
    private let store: any TokenStoring
    private let clock: any TimeProvider
    private let refresher: any TokenRefreshing

    public init(
        store: any TokenStoring,
        clock: any TimeProvider = SystemTimeProvider(),
        refresher: any TokenRefreshing
    ) {
        self.store = store
        self.clock = clock
        self.refresher = refresher
    }

    // MARK: - TokenProviding

    public func validToken() async throws -> String? {
        guard let tokens = store.load() else { return nil }

        if tokens.isNearlyExpired(at: clock.now) {
            let refreshed = try await refresher.performRefresh()
            return refreshed.idToken
        }
        return tokens.idToken
    }

    public func refresh() async throws {
        _ = try await refresher.performRefresh()
    }
}
