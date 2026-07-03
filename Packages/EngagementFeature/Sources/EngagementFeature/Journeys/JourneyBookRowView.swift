import SwiftUI
import DesignSystem
import Models

// MARK: - JourneyBookRowView

/// A single book row within the journey detail's book list.
///
/// Shows the order index, cover thumbnail (emoji fallback), title/author,
/// an optional "reason" subtitle, and a status indicator
/// (completed ✓, currently reading →, or locked).
struct JourneyBookRowView: View {

    let book: JourneyBookEntry
    let index: Int
    let isCompleted: Bool
    let isCurrent: Bool
    /// Called when the user taps the row (only active when `isCompleted` or `isCurrent`).
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: .cfSpacing12) {
                indexBadge
                coverThumbnail
                textContent
                Spacer()
                statusIcon
            }
            .padding(.cfSpacing12)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .buttonStyle(.plain)
        .disabled(!isCompleted && !isCurrent)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Sub-views

    private var indexBadge: some View {
        Text("\(index + 1)")
            .font(.cfCaption)
            .foregroundStyle(indexForeground)
            .frame(width: 24, height: 24)
            .background(indexBackground, in: Circle())
    }

    @ViewBuilder
    private var coverThumbnail: some View {
        let emoji = book.cover?.emoji ?? "📖"
        ZStack {
            RoundedRectangle(cornerRadius: .cfRadius8)
                .fill(Color.cfFill)
                .frame(width: 44, height: 60)
            Text(emoji)
                .font(.system(size: 24))
        }
        .frame(width: 44, height: 60)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(book.title)
                .font(.cfSubheadline)
                .foregroundStyle(isCurrent || isCompleted ? .primary : .secondary)
                .lineLimit(2)

            if let author = book.author {
                Text(author)
                    .font(.cfCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let reason = book.reason {
                Text(reason)
                    .font(.cfCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .italic()
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        } else if isCurrent {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(Color.cfAccent)
                .font(.title3)
        } else {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.cfTertiaryLabel)
                .font(.callout)
        }
    }

    // MARK: - Appearance helpers

    private var rowBackground: Color {
        if isCurrent { return Color.cfAccent.opacity(0.07) }
        return Color.cfSecondaryBackground
    }

    private var indexForeground: Color {
        isCompleted ? .white : (isCurrent ? .cfAccent : .secondary)
    }

    private var indexBackground: Color {
        if isCompleted { return .green }
        if isCurrent { return Color.cfAccent.opacity(0.15) }
        return Color.cfFill
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = ["Book \(index + 1)", book.title]
        if let author = book.author { parts.append("by \(author)") }
        if isCompleted { parts.append("Completed") } else if isCurrent { parts.append("Currently reading") } else { parts.append("Locked") }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if isCompleted || isCurrent { return "Double-tap to open this book" }
        return "Complete previous books to unlock"
    }
}
