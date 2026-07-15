@preconcurrency import Amplify
@preconcurrency import AWSCognitoAuthPlugin
@preconcurrency import AWSPluginsCore
import Foundation
import Persistence

/// Immutable app-owned snapshot of Amplify session state.
struct CognitoSessionSnapshot: Sendable, Equatable {
    let isSignedIn: Bool
    let tokens: StoredTokens?
}

/// Immutable app-owned snapshot of Amplify's current user.
struct CognitoUserSnapshot: Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let userId: String
    let username: String
    let email: String?

    var description: String { "CognitoUserSnapshot(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: ["contents": "redacted"])
    }
}

enum CognitoSignInOutcome: Sendable, Equatable {
    case signedIn
    case resetPassword
    case additionalStepRequired
}

enum CognitoSignOutOutcome: Sendable, Equatable {
    case signedOutLocally
    case failedLocally
}

/// Narrow seam around the Amplify operations that establish session truth.
protocol CognitoSessionClient: Sendable {
    func signIn(username: String, password: String) async throws -> CognitoSignInOutcome
    func fetchSession(forceRefresh: Bool) async throws -> CognitoSessionSnapshot
    func currentUser() async throws -> CognitoUserSnapshot
    func signOut() async -> CognitoSignOutOutcome
}

struct AmplifyCognitoSessionClient: CognitoSessionClient, Sendable {
    func signIn(username: String, password: String) async throws -> CognitoSignInOutcome {
        let result = try await Amplify.Auth.signIn(username: username, password: password)
        if result.isSignedIn { return .signedIn }
        if case .resetPassword = result.nextStep { return .resetPassword }
        return .additionalStepRequired
    }

    func fetchSession(forceRefresh: Bool) async throws -> CognitoSessionSnapshot {
        let options = AuthFetchSessionRequest.Options(forceRefresh: forceRefresh)
        let session = try await Amplify.Auth.fetchAuthSession(options: options)
        guard session.isSignedIn else {
            return CognitoSessionSnapshot(isSignedIn: false, tokens: nil)
        }
        guard let provider = session as? AuthCognitoTokensProvider else {
            return CognitoSessionSnapshot(isSignedIn: true, tokens: nil)
        }
        let amplifyTokens = try provider.getCognitoTokens().get()
        guard let expiry = cognitoTokenExpiry(from: amplifyTokens.idToken) else {
            return CognitoSessionSnapshot(isSignedIn: true, tokens: nil)
        }
        return CognitoSessionSnapshot(
            isSignedIn: true,
            tokens: StoredTokens(
                idToken: amplifyTokens.idToken,
                accessToken: amplifyTokens.accessToken,
                refreshToken: amplifyTokens.refreshToken,
                expiresAt: expiry
            )
        )
    }

    func currentUser() async throws -> CognitoUserSnapshot {
        let user = try await Amplify.Auth.getCurrentUser()
        return CognitoUserSnapshot(userId: user.userId, username: user.username, email: nil)
    }

    func signOut() async -> CognitoSignOutOutcome {
        guard let result = await Amplify.Auth.signOut() as? AWSCognitoSignOutResult,
              result.signedOutLocally else {
            return .failedLocally
        }
        return .signedOutLocally
    }
}

func cognitoTokenExpiry(from token: String) -> Date? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var payload = String(parts[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = payload.count % 4
    if remainder != 0 {
        payload += String(repeating: "=", count: 4 - remainder)
    }
    struct ExpiryClaims: Decodable { let exp: Double }
    guard let data = Data(base64Encoded: payload),
          let claims = try? JSONDecoder().decode(ExpiryClaims.self, from: data),
          claims.exp.isFinite,
          claims.exp > 0 else {
        return nil
    }
    return Date(timeIntervalSince1970: claims.exp)
}

struct VerifiedSession: Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let identity: SessionIdentity
    let tokens: StoredTokens

    var description: String { "VerifiedSession(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: ["contents": "redacted"])
    }
}
