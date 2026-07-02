import SwiftUI
import Models
import DesignSystem

/// A compact horizontal row of earned badge icons for the profile header area.
public struct BadgePreviewView: View {

    private let badges: [BadgeItem]
    private let badgeCount: Int
    private let maxVisible: Int

    /// - Parameters:
    ///   - badges: The earned badges (already filtered to `isEarned == true`).
    ///   - badgeCount: The server's total count (may exceed `badges.count` if paginated).
    ///   - maxVisible: How many badge icons to show before a "+N" overflow chip.
    public init(badges: [BadgeItem], badgeCount: Int, maxVisible: Int = 5) {
        self.badges = badges
        self.badgeCount = badgeCount
        self.maxVisible = maxVisible
    }

    public var body: some View {
        HStack(spacing: .cfSpacing8) {
            ForEach(badges.prefix(maxVisible)) { badge in
                badgeIcon(badge)
            }

            let overflow = badgeCount - min(badges.count, maxVisible)
            if overflow > 0 {
                overflowChip(count: overflow)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badgeCount) badges earned")
    }

    // MARK: - Sub-views

    private func badgeIcon(_ badge: BadgeItem) -> some View {
        ZStack {
            Circle()
                .fill(Color.cfAccent.opacity(0.12))
                .frame(width: 36, height: 36)
            if let icon = badge.icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.cfAccent)
            } else {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.cfAccent)
            }
        }
        .accessibilityLabel(badge.name)
    }

    private func overflowChip(count: Int) -> some View {
        Text("+\(count)")
            .font(.cfCaption)
            .foregroundStyle(Color.cfSecondaryLabel)
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, .cfSpacing4)
            .background(Color.cfFill, in: Capsule())
            .accessibilityLabel("\(count) more badges")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("BadgePreviewView") {
    BadgePreviewView(badges: BadgeItem.previewList, badgeCount: 8)
        .padding(.cfSpacing16)
        .background(Color.cfGroupedBackground)
}
#endif
