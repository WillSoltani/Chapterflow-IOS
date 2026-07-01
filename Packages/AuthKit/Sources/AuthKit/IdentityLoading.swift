import Foundation
import CoreKit
import Networking

// MARK: - Server response shapes (internal to AuthKit)

struct SessionResponse: Decodable, Sendable {
    let loggedIn: Bool
    let user: SessionUser?

    struct SessionUser: Decodable, Sendable {
        let sub: String?
        let email: String?
        let accountStatus: String?
    }
}

struct MeResponse: Decodable, Sendable {
    let user: MeUser

    struct MeUser: Decodable, Sendable {
        let sub: String
        let email: String
        let name: String?
        let displayName: String?
        let accountStatus: String?
        let profile: MeProfile?

        struct MeProfile: Decodable, Sendable {
            let displayName: String?
        }
    }
}

// MARK: - Session load result

/// The outcome of validating the current Cognito session with the server.
public enum SessionLoadResult: Sendable, Equatable {
    /// Session is valid; the user may proceed.
    case valid
    /// Token was rejected or the session has expired — sign the user out.
    case invalid
    /// Server reports the account has been deactivated.
    case deactivated
    /// Server reports the account has been deleted.
    case deleted
}

// MARK: - Protocol

/// Abstracts the identity network calls so `AppModel` is testable without a
/// real `APIClient`.
public protocol IdentityLoading: Sendable {
    func loadSession() async throws -> SessionLoadResult
    func loadProfile() async throws -> UserProfile
}

// MARK: - Concrete implementation

/// Fetches `GET /auth/session` and `GET /me` via an ``APIClientProtocol``.
public struct NetworkIdentityLoader: IdentityLoading {
    private let apiClient: any APIClientProtocol

    public init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    public func loadSession() async throws -> SessionLoadResult {
        let response: SessionResponse = try await apiClient.send(Endpoints.getSession())
        guard response.loggedIn else { return .invalid }
        if let status = response.user?.accountStatus {
            switch status {
            case "deactivated": return .deactivated
            case "deleted":     return .deleted
            default:            break
            }
        }
        return .valid
    }

    public func loadProfile() async throws -> UserProfile {
        let response: MeResponse = try await apiClient.send(Endpoints.getMe())
        let u = response.user
        // Resolution: profile.displayName > user.displayName > name > email prefix > "Reader"
        let displayName = u.profile?.displayName
            ?? u.displayName
            ?? u.name
            ?? Self.emailPrefix(u.email)
            ?? "Reader"
        let status = u.accountStatus
            .flatMap(UserProfile.AccountStatus.init(rawValue:))
            ?? .active
        return UserProfile(sub: u.sub, email: u.email, displayName: displayName, accountStatus: status)
    }

    private static func emailPrefix(_ email: String) -> String? {
        let prefix = email.components(separatedBy: "@").first ?? ""
        return prefix.isEmpty ? nil : prefix
    }
}
