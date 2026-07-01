import Foundation
import AuthenticationServices
import CoreKit

/// Handles the Sign-in-with-Apple → Cognito token exchange.
///
/// The flow:
///   1. `SignInWithAppleButton` (in `AuthFlowView`) requests Apple credentials
///      via the system native sheet.
///   2. Apple returns an `authorizationCode` (one-time, ~5 min TTL).
///   3. `exchangeAppleCode(_:name:)` POSTs it to the Cognito hosted-UI
///      token endpoint (`/oauth2/token`), which validates the code against
///      the configured Apple IdP and returns Cognito's own `id_token` /
///      `refresh_token`.
///   4. The caller stores the token set via `SessionManager.didSignIn`.
///
/// Prerequisites (Cognito pool setup):
///   - Apple configured as a social IdP in the User Pool
///   - `chapterflow://auth/callback` listed in the app client's allowed
///     callback URLs
///   - Hosted-UI custom domain set to `AppConfig.cognitoDomain`
public struct CognitoTokenClient: Sendable {
    private let config: AppConfig

    public init(config: AppConfig) {
        self.config = config
    }

    // MARK: - Apple authorization-code exchange

    /// Exchanges the Apple `authorizationCode` for a Cognito `TokenSet`.
    ///
    /// - Parameters:
    ///   - code: The raw `authorizationCode` bytes from `ASAuthorizationAppleIDCredential`.
    ///   - name: The `PersonNameComponents` Apple provides on first sign-in only;
    ///     used to seed `displayName` before the Cognito profile attribute syncs.
    /// - Returns: A `TokenSet` ready to pass to `SessionManager.didSignIn`, plus
    ///   an optional display name sourced from Apple's first-sign-in disclosure
    ///   or the returned id_token's JWT claims.
    public func exchangeAppleCode(
        _ code: Data,
        name: PersonNameComponents?
    ) async throws -> (tokens: TokenSet, displayName: String?) {
        guard !config.cognitoDomain.isEmpty, !config.cognitoClientID.isEmpty else {
            throw AppError.unauthenticated
        }

        guard let codeString = String(data: code, encoding: .utf8) else {
            throw AppError.unauthenticated
        }

        let tokenURL = URL(string: "https://\(config.cognitoDomain)/oauth2/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "grant_type": "authorization_code",
            "code": codeString,
            "redirect_uri": "chapterflow://auth/callback",
            "client_id": config.cognitoClientID,
        ]
        request.httpBody = params
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.unauthenticated
        }

        struct TokenResponse: Decodable {
            let id_token: String
            let refresh_token: String
        }
        let tokenResponse: TokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }

        let tokenSet = TokenSet(
            idToken: tokenResponse.id_token,
            refreshToken: tokenResponse.refresh_token
        )

        // Prefer the name Apple disclosed on first sign-in; fall back to JWT claims.
        let displayName: String? = resolveDisplayName(
            from: tokenResponse.id_token,
            appleNameComponents: name
        )

        return (tokens: tokenSet, displayName: displayName)
    }

    // MARK: - Helpers

    private func resolveDisplayName(
        from idToken: String,
        appleNameComponents: PersonNameComponents?
    ) -> String? {
        // Apple only provides name on first sign-in — use it when present.
        if let comps = appleNameComponents {
            let formatted = PersonNameComponentsFormatter().string(from: comps)
                .trimmingCharacters(in: .whitespaces)
            if !formatted.isEmpty { return formatted }
        }
        // Fall back to Cognito JWT claims.
        return UserProfile.from(idToken: idToken)?.displayName
    }

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
