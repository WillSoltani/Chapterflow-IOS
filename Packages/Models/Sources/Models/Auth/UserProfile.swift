/// The authenticated user's public profile.
///
/// Used by `AuthKit` and `SocialFeature`; decoded from the identity resolution
/// endpoint or embedded in the Cognito token claims.
public struct UserProfile: Codable, Sendable {
    public let userId: String
    public let email: String
    public let displayName: String?
    public let avatarUrl: String?
    public let createdAt: String?
}
