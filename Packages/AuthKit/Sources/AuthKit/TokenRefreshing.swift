import Foundation
import CoreKit
import Persistence

/// Performs a Cognito token refresh, returning the new `StoredTokens`.
public protocol TokenRefreshing: Sendable {
    func performRefresh() async throws -> StoredTokens
}

/// Stub for use in previews and unit tests.
/// Pass `shouldFail: true` to simulate a refresh failure.
public struct StubTokenRefresher: TokenRefreshing {
    private let shouldFail: Bool
    private let expiresIn: TimeInterval

    public init(shouldFail: Bool = false, expiresIn: TimeInterval = 3_600) {
        self.shouldFail = shouldFail
        self.expiresIn = expiresIn
    }

    public func performRefresh() async throws -> StoredTokens {
        if shouldFail { throw AppError.unauthenticated }
        return StoredTokens(
            idToken: "stub-id-token",
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token",
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }
}
