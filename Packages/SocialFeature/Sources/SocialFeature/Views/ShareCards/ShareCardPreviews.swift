#if DEBUG
import SwiftUI
import DesignSystem

// MARK: - Preview fixtures

extension ShareCardInput {
    public static let previewChapter = ShareCardInput.chapter(
        bookTitle: "Atomic Habits",
        bookEmoji: "⚛️",
        chapterNumber: 3,
        chapterTitle: "The 1% Rule: Marginal Gains Add Up",
        userName: "Alice Reader",
        tier: .analyst,
        referralCode: "ALICE42"
    )

    public static let previewBadgeStreak = ShareCardInput.badge(
        badgeName: "Week Streak",
        badgeDescription: "7 days of consecutive reading",
        badgeIcon: "flame.fill",
        category: "streak",
        userName: "Alice Reader",
        tier: .analyst,
        referralCode: "ALICE42"
    )

    public static let previewBadgeReading = ShareCardInput.badge(
        badgeName: "Bookworm",
        badgeDescription: "Finished 5 books",
        badgeIcon: "books.vertical.fill",
        category: "reading",
        userName: "Alice Reader",
        tier: .analyst,
        referralCode: "ALICE42"
    )

    public static let previewStreak = ShareCardInput.streak(
        days: 42,
        userName: "Alice Reader",
        tier: .analyst,
        referralCode: "ALICE42"
    )

    public static let previewBook = ShareCardInput.book(
        bookTitle: "Atomic Habits",
        bookEmoji: "⚛️",
        authorName: "James Clear",
        totalChapters: 20,
        userName: "Alice Reader",
        tier: .analyst,
        referralCode: "ALICE42"
    )

    public static let previewLuminaryStreak = ShareCardInput.streak(
        days: 365,
        userName: "Carol Luminary",
        tier: .luminary,
        referralCode: nil
    )
}

// MARK: - Card previews (light + dark + XXL)

#Preview("Chapter card — light") {
    ScrollView {
        ShareCardView(input: .previewChapter)
            .padding()
    }
}

#Preview("Chapter card — dark") {
    ScrollView {
        ShareCardView(input: .previewChapter)
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Chapter card — XXL") {
    ScrollView {
        ShareCardView(input: .previewChapter)
            .padding()
    }
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Badge — streak (light)") {
    ShareCardView(input: .previewBadgeStreak).padding()
}

#Preview("Badge — streak (dark)") {
    ShareCardView(input: .previewBadgeStreak)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Badge — reading (light)") {
    ShareCardView(input: .previewBadgeReading).padding()
}

#Preview("Streak card — light") {
    ShareCardView(input: .previewStreak).padding()
}

#Preview("Streak card — dark") {
    ShareCardView(input: .previewStreak)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Streak card — XXL") {
    ShareCardView(input: .previewStreak)
        .padding()
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Book card — light") {
    ShareCardView(input: .previewBook).padding()
}

#Preview("Book card — dark") {
    ShareCardView(input: .previewBook)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Book card — XXL") {
    ShareCardView(input: .previewBook)
        .padding()
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Luminary streak — no referral") {
    ShareCardView(input: .previewLuminaryStreak).padding()
}

#Preview("All card types") {
    ScrollView {
        VStack(spacing: 20) {
            ShareCardView(input: .previewChapter)
            ShareCardView(input: .previewBadgeStreak)
            ShareCardView(input: .previewStreak)
            ShareCardView(input: .previewBook)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
