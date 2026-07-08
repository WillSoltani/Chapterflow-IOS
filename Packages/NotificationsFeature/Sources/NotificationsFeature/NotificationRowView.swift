import SwiftUI
import Models
import DesignSystem

/// A single row in the notification inbox list.
///
/// Shows: type icon, title, body (2-line clamp), relative time, and an unread dot.
/// Tapping calls `onTap` with the resolved deep-link URL.
struct NotificationRowView: View {

    let notification: AppNotification
    let onTap: (URL) -> Void

    var body: some View {
        Button {
            if let url = NotificationInboxModel.routingURL(for: notification) {
                onTap(url)
            }
        } label: {
            HStack(alignment: .top, spacing: .cfSpacing12) {
                iconView
                textStack
                Spacer(minLength: 0)
                trailingStack
            }
            .padding(.vertical, .cfSpacing4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(notification.isRead ? "" : "Unread")
    }

    // MARK: - Sub-views

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(iconBackground)
                .frame(width: .cfIconLarge, height: .cfIconLarge)
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconForeground)
                .accessibilityHidden(true)
        }
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(notification.title)
                .font(.cfSubheadline.weight(.semibold))
                .foregroundStyle(Color.cfLabel)
                .lineLimit(1)
            Text(notification.body)
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
                .lineLimit(2)
        }
    }

    private var trailingStack: some View {
        VStack(alignment: .trailing, spacing: .cfSpacing8) {
            Text(relativeTime)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .lineLimit(1)
            if !notification.isRead {
                Circle()
                    .fill(Color.cfAccent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Type helpers

    /// SF Symbol name for the notification kind. Unknown types get a generic bell.
    private var iconName: String {
        switch notification.type {
        case .quizUnlocked:   return "checkmark.seal.fill"
        case .streakReminder: return "flame.fill"
        case .badgeEarned:    return "medal.fill"
        case .reviewDue:      return "clock.fill"
        case .unknown:        return "bell.fill"
        }
    }

    private var iconBackground: Color {
        switch notification.type {
        case .quizUnlocked:   return Color.cfAccent.opacity(0.12)
        case .streakReminder: return Color.orange.opacity(0.12)
        case .badgeEarned:    return Color.yellow.opacity(0.15)
        case .reviewDue:      return Color.purple.opacity(0.12)
        case .unknown:        return Color.cfSecondaryFill
        }
    }

    private var iconForeground: Color {
        switch notification.type {
        case .quizUnlocked:   return Color.cfAccent
        case .streakReminder: return Color.orange
        case .badgeEarned:    return Color.yellow
        case .reviewDue:      return Color.purple
        case .unknown:        return Color.cfSecondaryLabel
        }
    }

    // MARK: - Date

    private var relativeTime: String {
        guard let date = parseDate(notification.createdAt) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func parseDate(_ isoString: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: isoString) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: isoString)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let status = notification.isRead ? "" : "Unread. "
        return "\(status)\(notification.title). \(notification.body). \(relativeTime)"
    }
}
