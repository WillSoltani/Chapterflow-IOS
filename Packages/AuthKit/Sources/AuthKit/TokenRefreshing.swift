import Foundation
import CoreKit

/// Performs a Cognito token refresh using the stored refresh token.
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

// MARK: - Production implementation

/// Refreshes tokens via Cognito's `REFRESH_TOKEN_AUTH` InitiateAuth flow.
///
/// Direct HTTPS call to the Cognito service endpoint — no Amplify required.
/// Cognito does not always rotate the refresh token on refresh; when the
/// response omits it the existing token is reused.
public struct CognitoTokenRefresher: TokenRefreshing {
    private let config: AppConfig

    public init(config: AppConfig) {
        self.config = config
    }

    public func refreshTokens(using refreshToken: String) async throws -> TokenSet {
        guard !config.cognitoRegion.isEmpty, !config.cognitoClientID.isEmpty else {
            throw AppError.unauthenticated
        }

        let url = URL(string: "https://cognito-idp.\(config.cognitoRegion).amazonaws.com/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "AWSCognitoIdentityProviderService.InitiateAuth",
            forHTTPHeaderField: "X-Amz-Target"
        )

        let body: [String: Any] = [
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "AuthParameters": ["REFRESH_TOKEN": refreshToken],
            "ClientId": config.cognitoClientID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.unauthenticated
        }

        // Cognito returns PascalCase keys for this JSON API.
        struct InitiateAuthResponse: Decodable {
            struct AuthResult: Decodable {
                let IdToken: String?
                let RefreshToken: String?
            }
            let AuthenticationResult: AuthResult?
        }

        let decoded = try JSONDecoder().decode(InitiateAuthResponse.self, from: data)
        guard let idToken = decoded.AuthenticationResult?.IdToken else {
            throw AppError.unauthenticated
        }
        // Keep the existing refresh token if Cognito doesn't issue a new one.
        let newRefreshToken = decoded.AuthenticationResult?.RefreshToken ?? refreshToken
        return TokenSet(idToken: idToken, refreshToken: newRefreshToken)
    }
}

// MARK: - Test / preview stub

/// Stub used in previews and unit tests.
/// Pass `shouldFail: true` to simulate a refresh failure (triggers sign-out).
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
