import Foundation

public extension Endpoints {

    /// `POST /book/me/devices/register` — registers (or refreshes) an APNs device token.
    ///
    /// Per the B2 push contract: `platform` is always `"ios"` for native clients.
    /// The server upserts by `(userId, apnsToken)` so calling this with the same token
    /// is idempotent; calling it with a new token updates the stored record.
    static func registerDevice(
        apnsToken: String,
        bundleId: String,
        locale: String,
        timeZone: String
    ) throws -> Endpoint {
        struct Body: Encodable {
            let platform: String
            let apnsToken: String
            let bundleId: String
            let locale: String
            let timeZone: String
        }
        return try Endpoint(
            method: .post,
            path: "/book/me/devices/register",
            body: Body(
                platform: "ios",
                apnsToken: apnsToken,
                bundleId: bundleId,
                locale: locale,
                timeZone: timeZone
            )
        )
    }

    /// `POST /book/me/devices/unregister` — removes an APNs device token from the backend.
    ///
    /// Call on sign-out and on permission revocation so the backend stops targeting
    /// this device. Safe to call even if the token was never registered (server no-ops).
    static func unregisterDevice(apnsToken: String) throws -> Endpoint {
        struct Body: Encodable {
            let apnsToken: String
        }
        return try Endpoint(
            method: .post,
            path: "/book/me/devices/unregister",
            body: Body(apnsToken: apnsToken)
        )
    }
}
