import SwiftUI
import DesignSystem

// MARK: - Card constants

/// Fixed card canvas dimensions. Square = works on every social surface.
private let cardSize: CGFloat = 375

// MARK: - Gradient palettes (hardcoded — rendered to image, no semantic colors)

private extension ShareCardInput {
    var gradientColors: [Color] {
        switch self {
        case .chapter:
            return [Color(red: 0.07, green: 0.12, blue: 0.36), Color(red: 0.22, green: 0.42, blue: 0.85)]
        case .badge(_, _, _, let category, _, _, _):
            switch category.lowercased() {
            case "streak":
                return [Color(red: 0.55, green: 0.18, blue: 0.04), Color(red: 0.82, green: 0.44, blue: 0.14)]
            case "quiz":
                return [Color(red: 0.26, green: 0.08, blue: 0.48), Color(red: 0.58, green: 0.24, blue: 0.85)]
            default:
                return [Color(red: 0.07, green: 0.12, blue: 0.36), Color(red: 0.22, green: 0.42, blue: 0.85)]
            }
        case .streak:
            return [Color(red: 0.55, green: 0.18, blue: 0.04), Color(red: 0.87, green: 0.49, blue: 0.16)]
        case .book:
            return [Color(red: 0.06, green: 0.10, blue: 0.28), Color(red: 0.17, green: 0.34, blue: 0.64)]
        }
    }
}

// MARK: - Top brand bar

private struct CardBrandBar: View {
    var body: some View {
        HStack {
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("ChapterFlow")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
    }
}

// MARK: - User attribution row

private struct CardAttributionRow: View {
    let userName: String?
    let tier: ProfileTier

    private var initials: String {
        guard let name = userName, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        HStack(spacing: .cfSpacing8) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 28, height: 28)
                Text(initials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(userName ?? "ChapterFlow Reader")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(tier.displayLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
    }
}

// MARK: - Referral footer

private struct CardReferralFooter: View {
    let referralLink: String?

    var body: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "link")
                .font(.system(size: 9, weight: .medium))
            Text(referralLink.map { "Join me → \($0)" } ?? "app.chapterflow.ca")
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Separator

private struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(height: 0.5)
    }
}

// MARK: - Chapter card

struct ChapterShareCardView: View {
    let bookTitle: String
    let bookEmoji: String
    let chapterNumber: Int
    let chapterTitle: String
    let userName: String?
    let tier: ProfileTier
    let referralLink: String?
    let gradientColors: [Color]

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle texture overlay
            Color.white.opacity(0.03)
                .blendMode(.overlay)

            VStack(alignment: .leading, spacing: 0) {
                CardBrandBar()
                    .padding(.bottom, .cfSpacing12)

                Spacer(minLength: 0)

                // Book emoji + title
                HStack(spacing: .cfSpacing12) {
                    Text(bookEmoji.isEmpty ? "📚" : bookEmoji)
                        .font(.system(size: 44))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: .cfSpacing4) {
                        Text("CHAPTER \(chapterNumber)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .kerning(1.2)
                        Text(bookTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, .cfSpacing12)

                // Headline achievement text
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("Finished chapter")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .kerning(0.8)
                    Text(chapterTitle)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
                .padding(.bottom, .cfSpacing20)

                Spacer(minLength: 0)

                CardDivider()
                    .padding(.bottom, .cfSpacing12)

                CardAttributionRow(userName: userName, tier: tier)
                    .padding(.bottom, .cfSpacing8)

                CardReferralFooter(referralLink: referralLink)
            }
            .padding(.cfSpacing24)
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius24))
    }
}

// MARK: - Badge card

struct BadgeShareCardView: View {
    let badgeName: String
    let badgeDescription: String
    let badgeIcon: String?
    let category: String
    let userName: String?
    let tier: ProfileTier
    let referralLink: String?
    let gradientColors: [Color]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Decorative glow behind badge icon
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 140, height: 140)
                .blur(radius: 20)
                .offset(x: 80, y: -60)

            VStack(alignment: .leading, spacing: 0) {
                CardBrandBar()
                    .padding(.bottom, .cfSpacing12)

                Spacer(minLength: 0)

                // Badge icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: badgeIcon ?? "medal.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.bottom, .cfSpacing16)

                // Achievement label
                Text("Achievement Unlocked")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .kerning(1.0)
                    .padding(.bottom, .cfSpacing4)

                Text(badgeName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.bottom, .cfSpacing4)

                Text(badgeDescription)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .padding(.bottom, .cfSpacing20)

                Spacer(minLength: 0)

                CardDivider()
                    .padding(.bottom, .cfSpacing12)

                CardAttributionRow(userName: userName, tier: tier)
                    .padding(.bottom, .cfSpacing8)

                CardReferralFooter(referralLink: referralLink)
            }
            .padding(.cfSpacing24)
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius24))
    }
}

// MARK: - Streak card

struct StreakShareCardView: View {
    let days: Int
    let userName: String?
    let tier: ProfileTier
    let referralLink: String?
    let gradientColors: [Color]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )

            // Ambient glow
            Circle()
                .fill(Color(red: 1, green: 0.5, blue: 0.1).opacity(0.25))
                .frame(width: 200, height: 200)
                .blur(radius: 40)
                .offset(x: 60, y: -40)

            VStack(alignment: .leading, spacing: 0) {
                CardBrandBar()
                    .padding(.bottom, .cfSpacing8)

                Spacer(minLength: 0)

                // Flame emoji
                Text("🔥")
                    .font(.system(size: 52))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .padding(.bottom, .cfSpacing8)

                // Big streak number
                HStack(alignment: .lastTextBaseline, spacing: .cfSpacing4) {
                    Text("\(days)")
                        .font(.system(size: 80, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("days")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.bottom, .cfSpacing8)
                }
                .padding(.bottom, .cfSpacing4)

                Text("Reading streak")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, .cfSpacing20)

                Spacer(minLength: 0)

                CardDivider()
                    .padding(.bottom, .cfSpacing12)

                CardAttributionRow(userName: userName, tier: tier)
                    .padding(.bottom, .cfSpacing8)

                CardReferralFooter(referralLink: referralLink)
            }
            .padding(.cfSpacing24)
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius24))
    }
}

// MARK: - Book card

struct BookShareCardView: View {
    let bookTitle: String
    let bookEmoji: String
    let authorName: String?
    let totalChapters: Int
    let userName: String?
    let tier: ProfileTier
    let referralLink: String?
    let gradientColors: [Color]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            // Decorative radial glow
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 200, height: 200)
                .blur(radius: 30)
                .offset(x: -50, y: 60)

            VStack(alignment: .leading, spacing: 0) {
                CardBrandBar()
                    .padding(.bottom, .cfSpacing12)

                Spacer(minLength: 0)

                // Book emoji — large
                Text(bookEmoji.isEmpty ? "📖" : bookEmoji)
                    .font(.system(size: 56))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.bottom, .cfSpacing12)

                // "Finished" label
                Text("Just finished")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .kerning(1.0)
                    .padding(.bottom, .cfSpacing4)

                Text(bookTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, .cfSpacing4)

                if let author = authorName, !author.isEmpty {
                    Text("by \(author)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, .cfSpacing8)
                }

                // Chapter count badge
                HStack(spacing: .cfSpacing4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("\(totalChapters) chapters")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.bottom, .cfSpacing20)

                Spacer(minLength: 0)

                CardDivider()
                    .padding(.bottom, .cfSpacing12)

                CardAttributionRow(userName: userName, tier: tier)
                    .padding(.bottom, .cfSpacing8)

                CardReferralFooter(referralLink: referralLink)
            }
            .padding(.cfSpacing24)
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius24))
    }
}

// MARK: - Unified dispatcher

/// Renders the appropriate share card view for any ``ShareCardInput``.
///
/// This is the view passed to `ImageRenderer` at share time.
public struct ShareCardView: View {
    public let input: ShareCardInput

    public init(input: ShareCardInput) {
        self.input = input
    }

    public var body: some View {
        let colors = input.gradientColors
        switch input {
        case let .chapter(bookTitle, bookEmoji, chapterNumber, chapterTitle, userName, tier, _):
            ChapterShareCardView(
                bookTitle: bookTitle,
                bookEmoji: bookEmoji,
                chapterNumber: chapterNumber,
                chapterTitle: chapterTitle,
                userName: userName,
                tier: tier,
                referralLink: input.referralLink,
                gradientColors: colors
            )

        case let .badge(badgeName, badgeDesc, badgeIcon, category, userName, tier, _):
            BadgeShareCardView(
                badgeName: badgeName,
                badgeDescription: badgeDesc,
                badgeIcon: badgeIcon,
                category: category,
                userName: userName,
                tier: tier,
                referralLink: input.referralLink,
                gradientColors: colors
            )

        case let .streak(days, userName, tier, _):
            StreakShareCardView(
                days: days,
                userName: userName,
                tier: tier,
                referralLink: input.referralLink,
                gradientColors: colors
            )

        case let .book(bookTitle, bookEmoji, authorName, totalChapters, userName, tier, _):
            BookShareCardView(
                bookTitle: bookTitle,
                bookEmoji: bookEmoji,
                authorName: authorName,
                totalChapters: totalChapters,
                userName: userName,
                tier: tier,
                referralLink: input.referralLink,
                gradientColors: colors
            )
        }
    }
}
