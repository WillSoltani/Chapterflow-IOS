import Foundation

/// A minimal identity record for the signed-in user.
///
/// Populated from `GET /auth/session` + `GET /me` on cold launch, persisted
/// in `UserDefaults` for instant-launch display, and exposed app-wide via
/// `EnvironmentValues.currentUser`.
public struct UserProfile: Codable, Equatable, Sendable {

    public let sub: String
    public let email: String
    public let displayName: String
    public let accountStatus: AccountStatus

    public enum AccountStatus: String, Codable, Sendable, Equatable {
        case active
        case deactivated
        case deleted

        /// Resilient decoding — unknown server values fall back to `.active`
        /// so the app keeps working if the server adds new statuses.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = AccountStatus(rawValue: raw) ?? .active
        }
    }

    public init(
        sub: String,
        email: String,
        displayName: String,
        accountStatus: AccountStatus = .active
    ) {
        self.sub = sub
        self.email = email
        self.displayName = displayName
        self.accountStatus = accountStatus
    }
}
