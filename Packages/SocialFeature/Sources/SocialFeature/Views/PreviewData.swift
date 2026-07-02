#if DEBUG
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

    /// Repository in error state (every call throws `.offline`).
    public static var errored: FakeSocialRepository {
        FakeSocialRepository(error: .offline)
    }
}
#endif
