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
    public static let fixedIDToken: String = {
        let payload = Data(
            #"{"sub":"test-subject","exp":9999999999,"name":"Test Reader"}"#.utf8
        )
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(payload).signature"
    }()

    private let shouldFail: Bool
    private let expiresIn: TimeInterval

    public init(shouldFail: Bool = false, expiresIn: TimeInterval = 3_600) {
        self.shouldFail = shouldFail
        self.expiresIn = expiresIn
    }

    public func performRefresh() async throws -> StoredTokens {
        if shouldFail { throw AppError.unauthenticated }
        return StoredTokens(
            idToken: Self.fixedIDToken,
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token",
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }
}
