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
    private var pairs: [ReadingPair]
    private var gifts: [String: Gift]
    private var giftCodeCounter: Int = 0
    private let forcedError: AppError?

    /// Every `UpdateSettingsBody` that `updateSettings` has been called with, in order.
    public private(set) var recordedUpdates: [UpdateSettingsBody] = []

    /// Partner IDs that have been nudged (for test assertions).
    public private(set) var recordedNudges: [String] = []

    /// Partner IDs that have been deleted (for test assertions).
    public private(set) var recordedDeletes: [String] = []

    public init(
        profile: OwnProfile = OwnProfile.preview,
        badges: [BadgeItem] = BadgeItem.previewList,
        publicProfiles: [String: PublicProfile] = [:],
        pairs: [ReadingPair] = [],
        gifts: [String: Gift] = [:],
        error: AppError? = nil
    ) {
        self.profile = profile
        self.badges = badges
        self.publicProfiles = publicProfiles
        self.pairs = pairs
        self.gifts = gifts
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

    // MARK: - Reading pairs

    public func getPairs() async throws -> [ReadingPair] {
        if let err = forcedError { throw err }
        return pairs
    }

    public func createInvite() async throws -> PairInvite {
        if let err = forcedError { throw err }
        return PairInvite(
            code: "FAKE-CODE-1234",
            inviteLink: "https://chapterflow.app/pair/accept/FAKE-CODE-1234",
            expiresAt: "2026-07-10T00:00:00Z"
        )
    }

    public func acceptInvite(code: String) async throws -> ReadingPair {
        if let err = forcedError { throw err }
        let newPair = ReadingPair.preview(partnerId: "accepted-\(code)")
        pairs.append(newPair)
        return newPair
    }

    public func getPair(partnerId: String) async throws -> ReadingPair {
        if let err = forcedError { throw err }
        return pairs.first { $0.partnerId == partnerId } ?? .preview(partnerId: partnerId)
    }

    public func deletePair(partnerId: String) async throws {
        if let err = forcedError { throw err }
        recordedDeletes.append(partnerId)
        pairs.removeAll { $0.partnerId == partnerId }
    }

    public func nudgePartner(partnerId: String) async throws {
        if let err = forcedError { throw err }
        recordedNudges.append(partnerId)
    }

    // MARK: - Gifts

    public func getGift(code: String) async throws -> Gift {
        if let err = forcedError { throw err }
        guard let gift = gifts[code] else {
            throw AppError.notFound
        }
        return gift
    }

    public func claimGift(code: String) async throws -> GiftClaimResult {
        if let err = forcedError { throw err }
        guard let gift = gifts[code] else {
            throw AppError.notFound
        }
        switch gift.status {
        case .claimed:
            throw AppError.server(
                code: "gift_already_claimed",
                message: "This gift has already been redeemed.",
                requestId: nil
            )
        case .expired:
            throw AppError.server(
                code: "gift_expired",
                message: "This gift code has expired.",
                requestId: nil
            )
        case .pending, .unknown:
            let claimed = Gift(
                code: gift.code,
                giftType: gift.giftType,
                senderDisplayName: gift.senderDisplayName,
                status: .claimed,
                createdAt: gift.createdAt,
                expiresAt: gift.expiresAt
            )
            gifts[code] = claimed
            return GiftClaimResult(gift: claimed, message: "Pro access activated for 7 days!")
        }
    }

    public func createGift(giftType: String) async throws -> Gift {
        if let err = forcedError { throw err }
        giftCodeCounter += 1
        let code = "GIFT\(String(format: "%04d", giftCodeCounter))"
        let gift = Gift(
            code: code,
            giftType: giftType,
            senderDisplayName: profile.displayName,
            status: .pending,
            createdAt: nil,
            expiresAt: nil
        )
        gifts[code] = gift
        return gift
    }
}
