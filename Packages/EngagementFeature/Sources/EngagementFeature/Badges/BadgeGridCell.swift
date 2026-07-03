import SwiftUI
import DesignSystem
import Models

// MARK: - BadgeGridCell

/// A single cell in the badges grid.
///
/// States:
/// - **Earned** — full opacity, coloured icon, name beneath.
/// - **Locked (visible)** — dimmed, lock overlay, optional progress ring.
/// - **Locked (hidden track)** — "???" name, no criteria, lock overlay.
struct BadgeGridCell: View {

    let badge: BadgeItem

    private var track: AchievementTrack? {
        AchievementTrack.from(category: badge.category)
    }

    private var isHiddenTrack: Bool { track == .hidden }

    var body: some View {
        VStack(spacing: .cfSpacing8) {
            iconStack
            nameLabel
        }
        .padding(.cfSpacing8)
        .opacity(badge.isEarned ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(badge.isEarned ? "Tap to see details" : "Locked. Tap for requirements.")
    }

    // MARK: - Icon stack

    private var iconStack: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(iconBackground)
                .frame(width: 60, height: 60)

            // Badge icon or placeholder
            iconContent
                .frame(width: 60, height: 60)

            // Progress ring for locked badges with progress data
            if !badge.isEarned, let fraction = badge.progressFraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.cfAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 64, height: 64)
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }

            // Lock overlay for unearned badges
            if !badge.isEarned {
                lockBadge
            }
        }
    }

    @ViewBuilder
    private var iconContent: some View {
        if !badge.isEarned && isHiddenTrack {
            Image(systemName: "questionmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.secondary)
        } else if let emoji = badge.icon, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 28))
        } else {
            Image(systemName: "medal.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(iconTint)
        }
    }

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(Color.cfSecondaryLabel, in: Circle())
            .offset(x: 20, y: 20)
    }

    // MARK: - Name label

    @ViewBuilder
    private var nameLabel: some View {
        if !badge.isEarned && isHiddenTrack {
            Text("???")
                .font(.cfCaption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        } else {
            Text(badge.name)
                .font(.cfCaption2)
                .foregroundStyle(badge.isEarned ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    // MARK: - Helpers

    private var iconBackground: Color {
        badge.isEarned ? trackColor.opacity(0.12) : Color.cfSecondaryFill
    }

    private var iconTint: Color { trackColor }

    private var trackColor: Color {
        switch track {
        case .mastery:     return .cfAccent
        case .consistency: return .orange
        case .exploration: return .green
        case .hidden:      return .purple
        case .none:        return .cfSecondaryLabel
        }
    }

    private var accessibilityLabel: String {
        if !badge.isEarned && isHiddenTrack {
            return "Hidden achievement, locked"
        }
        let state = badge.isEarned ? "Earned" : "Locked"
        return "\(badge.name), \(state)"
    }
}
