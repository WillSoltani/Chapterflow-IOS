import Foundation

public extension Endpoints {

    /// `GET /book/me/settings` — returns the user's server-side settings,
    /// including the `notifications` block used by the Notification Settings screen.
    static func getSettings() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/settings", requiresAuth: true)
    }

    /// `PATCH /book/me/settings` — persists notification preference fields.
    ///
    /// Sends only the `notifications` sub-object so other setting fields are
    /// not disturbed. Uses the existing generic `updateSettings` factory.
    static func patchNotificationSettings<Body: Encodable & Sendable>(_ body: Body) throws -> Endpoint {
        try Endpoint(method: .patch, path: "/book/me/settings", body: body)
    }
}
