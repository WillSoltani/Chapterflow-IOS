#if DEBUG
import Foundation
import Models

// MARK: - OwnProfile preview fixtures

extension OwnProfile {
    public static let preview = OwnProfile(
        userId: "user-alice",
        displayName: "Alice Reader",
        avatarUrl: nil,
        avatarEmoji: nil,
        tier: .analyst,
        tierProgress: 0.65,
        currentStreak: 14,
        longestStreak: 21,
        booksFinished: 7,
        flowPoints: 4_200,
        equippedFrame: CosmeticItem(
            itemId: "frame-gold-wave",
            name: "Gold Wave",
            itemType: .avatarFrame,
            rarity: "rare"
        ),
        equippedTheme: CosmeticItem(
            itemId: "theme-midnight",
            name: "Midnight",
            itemType: .profileTheme,
            rarity: "uncommon"
        ),
        badgeCount: 8,
        joinedAt: "2024-01-01T00:00:00Z"
    )

    public static let previewNoCosmetics = OwnProfile(
        userId: "user-bob",
        displayName: "Bob",
        avatarUrl: nil,
        avatarEmoji: "📚",
        tier: .reader,
        tierProgress: 0.20,
        currentStreak: 3,
        longestStreak: 7,
        booksFinished: 1,
        flowPoints: 200,
        equippedFrame: nil,
        equippedTheme: nil,
        badgeCount: 1,
        joinedAt: "2024-06-01T00:00:00Z"
    )

    public static let previewLuminary = OwnProfile(
        userId: "user-carol",
        displayName: "Carol Luminary",
        avatarUrl: nil,
        avatarEmoji: "✨",
        tier: .luminary,
        tierProgress: 0.95,
        currentStreak: 365,
        longestStreak: 365,
        booksFinished: 42,
        flowPoints: 99_999,
        equippedFrame: CosmeticItem(
            itemId: "frame-stellar",
            name: "Stellar",
            itemType: .avatarFrame,
            rarity: "legendary"
        ),
        equippedTheme: nil,
        badgeCount: 30,
        joinedAt: "2023-01-01T00:00:00Z"
    )
}

// MARK: - PublicProfile preview fixtures

extension PublicProfile {
    public static func preview(userId: String = "user-partner") -> PublicProfile {
        PublicProfile(
            userId: userId,
            displayName: "Reading Partner",
            avatarUrl: nil,
            avatarEmoji: "🎯",
            tier: .synthesizer,
            currentStreak: 9,
            booksFinished: 12,
            equippedFrame: CosmeticItem(
                itemId: "frame-silver",
                name: "Silver",
                itemType: .avatarFrame,
                rarity: "uncommon"
            ),
            equippedTheme: nil,
            badgeCount: 5,
            joinedAt: "2024-03-01T00:00:00Z"
        )
    }
}

// MARK: - BadgeItem preview fixtures

extension BadgeItem {
    public static let previewList: [BadgeItem] = [
        BadgeItem(
            badgeId: "badge-first-book",
            name: "First Chapter",
            description: "Completed your first chapter",
            category: "reading",
            isEarned: true,
            earnedAt: "2024-01-10T10:00:00Z",
            icon: "book.fill"
        ),
        BadgeItem(
            badgeId: "badge-streak-7",
            name: "Week Streak",
            description: "7-day reading streak",
            category: "streak",
            isEarned: true,
            earnedAt: "2024-01-17T09:00:00Z",
            icon: "flame.fill"
        ),
        BadgeItem(
            badgeId: "badge-quiz-ace",
            name: "Quiz Ace",
            description: "100% on a chapter quiz",
            category: "quiz",
            isEarned: true,
            earnedAt: "2024-01-12T14:00:00Z",
            icon: "star.fill"
        ),
        BadgeItem(
            badgeId: "badge-bookworm",
            name: "Bookworm",
            description: "Finished 5 books",
            category: "reading",
            isEarned: true,
            earnedAt: "2024-02-01T11:00:00Z",
            icon: "books.vertical.fill"
        ),
    ]
}

// MARK: - ReadingPair preview fixtures

extension ReadingPair {
    public static let previewActive = ReadingPair(
        partnerId: "user-bob",
        partnerDisplayName: "Bob Smith",
        partnerAvatarUrl: nil,
        partnerAvatarEmoji: "📚",
        partnerTier: .analyst,
        partnerCurrentStreak: 7,
        partnerBooksFinished: 4,
        status: .active,
        pairedAt: "2024-03-01T00:00:00Z"
    )

    public static let previewPending = ReadingPair(
        partnerId: "user-carol-pending",
        partnerDisplayName: "Carol",
        partnerAvatarUrl: nil,
        partnerAvatarEmoji: "✨",
        partnerTier: .reader,
        partnerCurrentStreak: 0,
        partnerBooksFinished: 0,
        status: .pending,
        pairedAt: nil
    )

    public static let previewExpired = ReadingPair(
        partnerId: "user-dave-expired",
        partnerDisplayName: "Dave",
        partnerAvatarUrl: nil,
        partnerAvatarEmoji: "📖",
        partnerTier: .reader,
        partnerCurrentStreak: 0,
        partnerBooksFinished: 0,
        status: .expired,
        pairedAt: nil
    )

    public static func preview(partnerId: String, displayName: String? = nil) -> ReadingPair {
        ReadingPair(
            partnerId: partnerId,
            partnerDisplayName: displayName ?? "Partner \(partnerId.prefix(4).uppercased())",
            partnerAvatarUrl: nil,
            partnerAvatarEmoji: "🤝",
            partnerTier: .analyst,
            partnerCurrentStreak: 5,
            partnerBooksFinished: 3,
            status: .active,
            pairedAt: "2024-04-01T00:00:00Z"
        )
    }
}

// MARK: - Gift preview fixtures

extension Gift {
    /// A pending gift ready to be claimed.
    public static let previewPending = Gift(
        code: "GIFT0001",
        giftType: "pro_week",
        senderDisplayName: "Alice Reader",
        status: .pending,
        createdAt: "2026-07-03T10:00:00Z",
        expiresAt: "2026-07-10T10:00:00Z"
    )

    /// A gift that has already been redeemed.
    public static let previewClaimed = Gift(
        code: "CLMD0001",
        giftType: "pro_week",
        senderDisplayName: "Bob",
        status: .claimed,
        createdAt: "2026-06-01T09:00:00Z",
        expiresAt: nil
    )

    /// A gift that has expired.
    public static let previewExpired = Gift(
        code: "EXPD0001",
        giftType: "pro_week",
        senderDisplayName: nil,
        status: .expired,
        createdAt: "2026-06-01T09:00:00Z",
        expiresAt: "2026-06-08T09:00:00Z"
    )
}

// MARK: - FakeSocialRepository preview helpers

extension FakeSocialRepository {
    /// Loaded repository seeded with preview data.
    public static var loaded: FakeSocialRepository {
        FakeSocialRepository(
            profile: .preview,
            badges: BadgeItem.previewList,
            publicProfiles: ["user-partner": .preview()]
        )
    }

    /// Repository with a pending gift for claim-flow previews.
    public static var withPendingGift: FakeSocialRepository {
        FakeSocialRepository(
            profile: .preview,
            badges: BadgeItem.previewList,
            gifts: ["GIFT0001": .previewPending]
        )
    }

    /// Repository with an already-claimed gift (triggers the "already redeemed" error).
    public static var withClaimedGift: FakeSocialRepository {
        FakeSocialRepository(
            profile: .preview,
            badges: BadgeItem.previewList,
            gifts: ["CLMD0001": .previewClaimed]
        )
    }

    /// Repository in error state (every call throws `.offline`).
    public static var errored: FakeSocialRepository {
        FakeSocialRepository(error: .offline)
    }

    /// Repository seeded with multiple reading pairs for pairs-screen previews.
    public static var withPairs: FakeSocialRepository {
        FakeSocialRepository(
            profile: .preview,
            badges: BadgeItem.previewList,
            publicProfiles: ["user-partner": .preview()],
            pairs: [.previewActive, .previewPending, .previewExpired]
        )
    }

    /// Repository seeded with reflections for reflections-screen previews.
    public static var reflectionsPreview: FakeSocialRepository {
        let reflections = [
            ChapterReflection(
                reflectionId: "r1",
                bookId: "atomic-habits",
                chapterN: 3,
                text: "The habit loop diagram clicked for me — cue, routine, reward. I've been running on autopilot and never realised how many cues are controlling my day.",
                createdAt: Date(timeIntervalSinceNow: -86400 * 3),
                feedbackText: "You've noticed something fundamental: awareness is the first step to change. The habit loop reveals that most of our behaviour is triggered before we even think about it. Recognising your cues is already a powerful shift."
            ),
            ChapterReflection(
                reflectionId: "r2",
                bookId: "atomic-habits",
                chapterN: 3,
                text: "I want to try habit stacking — link my new reading habit to my morning coffee.",
                createdAt: Date(timeIntervalSinceNow: -86400),
                feedbackText: nil
            ),
        ]
        return FakeSocialRepository(
            profile: .preview,
            badges: BadgeItem.previewList,
            serverReflections: ["atomic-habits": ["3": reflections]]
        )
    }
}

// MARK: - ChapterReflection preview fixtures

extension ChapterReflection {
    public static func preview(
        id: String = "r-preview",
        bookId: String = "atomic-habits",
        chapterN: Int = 3,
        text: String = "A short preview reflection for tests and snapshots.",
        feedbackText: String? = nil
    ) -> ChapterReflection {
        ChapterReflection(
            reflectionId: id,
            bookId: bookId,
            chapterN: chapterN,
            text: text,
            createdAt: Date(timeIntervalSinceNow: -3600),
            feedbackText: feedbackText
        )
    }
}
#endif
