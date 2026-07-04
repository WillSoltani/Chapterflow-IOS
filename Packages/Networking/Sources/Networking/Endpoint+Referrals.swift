import Foundation

extension Endpoints {

    // MARK: - Referrals

    /// `GET /book/me/referrals` → `{ referral: { code, shareUrl?, stats, rewards } }`.
    ///
    /// Returns the authenticated user's referral profile including their invite code,
    /// share URL, aggregated stats, and all earned / pending rewards.
    public static func getReferralProfile() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/referrals", requiresAuth: true)
    }

    /// `POST /book/me/referrals/apply` — attributes a referral code to the current user.
    ///
    /// Used when the user manually types or pastes a friend's code after installing
    /// the app without clicking a referral link. The server attributes the referral
    /// and may grant rewards; never grant anything client-side.
    /// - Parameter code: The referral code to apply (e.g. `"ALICE42"`).
    public static func applyReferralCode(_ code: String) throws -> Endpoint {
        struct Body: Encodable { let code: String }
        return try Endpoint(
            method: .post,
            path: "/book/me/referrals/apply",
            body: Body(code: code)
        )
    }
}
