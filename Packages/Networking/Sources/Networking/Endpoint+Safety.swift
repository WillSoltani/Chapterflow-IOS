import Foundation

// MARK: - Safety endpoints
// ⚠️ Backend TODO: All endpoints below are client-contract definitions.
// The production API does not yet implement them. Backend team must add:
//   POST   /book/me/blocks              — block a user
//   DELETE /book/me/blocks/{userId}     — unblock a user
//   GET    /book/me/blocks              — list blocked users
//   POST   /book/moderation/reports     — submit a moderation report
//
// Expected request / response shapes are documented on each factory below.
// Until the backend is live, LiveSocialRepository will surface an AppError.server
// for these calls; FakeSocialRepository simulates them in-memory.

extension Endpoints {

    // MARK: - Block / unblock

    /// `POST /book/me/blocks` — block `userId`.
    ///
    /// Request body: `{ "userId": "<string>" }`
    /// Response (200): `{ "success": true }`
    public static func blockUser(userId: String) throws -> Endpoint {
        struct Body: Encodable { let userId: String }
        return try Endpoint(method: .post, path: "/book/me/blocks", body: Body(userId: userId))
    }

    /// `DELETE /book/me/blocks/{userId}` — unblock a previously blocked user.
    ///
    /// No request body.
    /// Response (200): `{ "success": true }`
    public static func unblockUser(userId: String) -> Endpoint {
        Endpoint(method: .delete, path: "/book/me/blocks/\(userId)")
    }

    /// `GET /book/me/blocks` — fetch the current user's blocked-user list.
    ///
    /// Response (200): `{ "blockedUsers": [{ "userId": "<string>", "blockedAt": "<iso8601>" }] }`
    public static func getBlockedUsers() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/blocks")
    }

    // MARK: - Moderation reports

    /// `POST /book/moderation/reports` — submit a moderation report.
    ///
    /// At least one of `targetUserId` / `contentId` must be provided.
    ///
    /// Request body:
    /// ```json
    /// {
    ///   "targetUserId": "<string|null>",
    ///   "contentId": "<string|null>",
    ///   "contentType": "<string|null>",
    ///   "reason": "<string>",
    ///   "details": "<string|null>"
    /// }
    /// ```
    /// Response (201): `{ "reportId": "<string>", "status": "received" }`
    /// On 429: standard `{ "error": { "code": "rate_limited", ... } }` envelope.
    public static func submitReport(
        targetUserId: String?,
        contentId: String?,
        contentType: String?,
        reason: String,
        details: String?
    ) throws -> Endpoint {
        struct Body: Encodable {
            let targetUserId: String?
            let contentId: String?
            let contentType: String?
            let reason: String
            let details: String?
        }
        return try Endpoint(
            method: .post,
            path: "/book/moderation/reports",
            body: Body(
                targetUserId: targetUserId,
                contentId: contentId,
                contentType: contentType,
                reason: reason,
                details: details
            )
        )
    }
}
