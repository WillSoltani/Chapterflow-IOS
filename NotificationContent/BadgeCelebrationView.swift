import SwiftUI

/// Custom expanded notification UI shown when the user long-presses a
/// `CF_BADGE_EARNED` push notification.
///
/// Driven from the push payload only (RF4). No network calls, no SwiftData.
struct BadgeCelebrationView: View {
    let badgeName: String
    let badgeKey: String

    var body: some View {
        VStack(spacing: 20) {
            badgeIcon
                .padding(.top, 24)

            VStack(spacing: 6) {
                Text("Badge Earned")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(badgeName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var badgeIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        // cfAccent value from DesignSystem, replicated here because
                        // content extensions are a separate binary that cannot import
                        // DesignSystem without adding a redundant project dependency.
                        colors: [Color(red: 0.18, green: 0.40, blue: 0.82), .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)

            Image(systemName: systemImageName)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var systemImageName: String {
        if badgeKey.contains("streak") { return "flame.fill" }
        if badgeKey.contains("chapter") { return "book.fill" }
        if badgeKey.contains("quiz") { return "checkmark.seal.fill" }
        if badgeKey.contains("social") { return "person.2.fill" }
        return "trophy.fill"
    }
}

// MARK: - Previews

#Preview("Badge — Default (light)") {
    BadgeCelebrationView(badgeName: "First Chapter Complete", badgeKey: "first_chapter")
        .frame(height: 260)
}

#Preview("Badge — Streak (dark)", traits: .colorScheme(.dark)) {
    BadgeCelebrationView(badgeName: "7-Day Reading Streak", badgeKey: "streak_7")
        .frame(height: 260)
}

#Preview("Badge — Quiz") {
    BadgeCelebrationView(badgeName: "Quiz Champion", badgeKey: "quiz_perfect")
        .frame(height: 260)
}

#Preview("Badge — XXL type", traits: .sizeCategoryXXXL) {
    BadgeCelebrationView(badgeName: "First Chapter Complete", badgeKey: "first_chapter")
        .frame(height: 320)
}
