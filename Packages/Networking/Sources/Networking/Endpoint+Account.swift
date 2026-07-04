import Foundation

// MARK: - Account lifecycle endpoints

public extension Endpoints {

    /// `GET /book/me/export` — request a full JSON export of the user's data.
    /// Returns the raw export payload; callers use `APIClientProtocol.sendData`.
    static func getExport() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/export", requiresAuth: true)
    }

    /// `POST /book/me/account/deactivate` — temporarily deactivates the account.
    /// The server pauses content access; the account can be reactivated by signing in again.
    static func deactivateAccount() throws -> Endpoint {
        struct Body: Encodable {}
        return try Endpoint(method: .post, path: "/book/me/account/deactivate", body: Body())
    }

    /// `POST /book/me/account/delete` — permanently deletes the account.
    /// The server revokes the Apple Sign-In token (B8) server-side before deleting.
    /// The client must sign out immediately on success.
    static func deleteAccount() throws -> Endpoint {
        struct Body: Encodable {}
        return try Endpoint(method: .post, path: "/book/me/account/delete", body: Body())
    }
}
