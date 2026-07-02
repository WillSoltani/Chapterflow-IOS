import Models
import CoreKit

/// In-memory ``SocialRepository`` for unit tests and SwiftUI previews.
///
/// Seed it with fixture data at construction; inject into ``ProfileModel`` /
/// ``PublicProfileModel``; observe mutations via `recordedUpdates`.
/// An optional `forcedError` makes every method throw — useful for error-state tests.
public actor FakeSocialRepository: SocialRepository {

    private var profile: OwnProfile
    private var badges: [BadgeItem]
    private var publicProfiles: [String: PublicProfile]
    private let forcedError: AppError?

    /// Every `UpdateSettingsBody` that `updateSettings` has been called with, in order.
    public private(set) var recordedUpdates: [UpdateSettingsBody] = []

    public init(
        profile: OwnProfile = OwnProfile.preview,
        badges: [BadgeItem] = BadgeItem.previewList,
        publicProfiles: [String: PublicProfile] = [:],
        error: AppError? = nil
    ) {
        self.profile = profile
        self.badges = badges
        self.publicProfiles = publicProfiles
        self.forcedError = error
    }

    // MARK: - SocialRepository

    public func getMyProfile() async throws -> OwnProfile {
        if let err = forcedError { throw err }
        return profile
    }

    public func getMyBadges() async throws -> [BadgeItem] {
        if let err = forcedError { throw err }
        return badges
    }

    public func updateSettings(_ body: UpdateSettingsBody) async throws -> OwnProfile {
        if let err = forcedError { throw err }
        recordedUpdates.append(body)
        let updated = OwnProfile(
            userId: profile.userId,
            displayName: body.displayName ?? profile.displayName,
            avatarUrl: profile.avatarUrl,
            avatarEmoji: body.avatarEmoji ?? profile.avatarEmoji,
            tier: profile.tier,
            tierProgress: profile.tierProgress,
            currentStreak: profile.currentStreak,
            longestStreak: profile.longestStreak,
            booksFinished: profile.booksFinished,
            flowPoints: profile.flowPoints,
            equippedFrame: profile.equippedFrame,
            equippedTheme: profile.equippedTheme,
            badgeCount: profile.badgeCount,
            joinedAt: profile.joinedAt
        )
        profile = updated
        return updated
    }

    public func getPublicProfile(userId: String) async throws -> PublicProfile {
        if let err = forcedError { throw err }
        return publicProfiles[userId] ?? PublicProfile.preview(userId: userId)
    }
}
