import Foundation
import CoreKit

/// Performs a Cognito token refresh using the stored refresh token.
///
/// The concrete Amplify-backed implementation lives in P1.5 and is injected
/// into `SessionManager`. `StubTokenRefresher` is provided for previews/tests.
public protocol TokenRefreshing: Sendable {
    /// Refreshes the Cognito session and returns new tokens.
    func refreshTokens(using refreshToken: String) async throws -> TokenSet
}

/// A refreshed set of Cognito tokens returned after a successful refresh.
public struct TokenSet: Sendable {
    public let idToken: String
    public let refreshToken: String

    public init(idToken: String, refreshToken: String) {
        self.idToken = idToken
        self.refreshToken = refreshToken
    }
}

/// Stub used in previews and unit tests.
/// - Pass `shouldFail: true` to simulate a refresh failure (triggers sign-out).
public struct StubTokenRefresher: TokenRefreshing {
    private let shouldFail: Bool

    public init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    public func refreshTokens(using refreshToken: String) async throws -> TokenSet {
        if shouldFail { throw AppError.unauthenticated }
        return TokenSet(
            idToken: "stub-id-\(refreshToken.prefix(6))",
            refreshToken: refreshToken
        )
    }
}
