import SwiftUI
import DesignSystem
import Models

// MARK: - NotebookEntryRowView

/// A single row in the Notebook list showing entry type, content preview,
/// book/chapter context, tags, and relative date.
struct NotebookEntryRowView: View {

    let entry: NotebookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            // Header: type icon + book context
            HStack(spacing: .cfSpacing8) {
                typeIcon
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(typeColor)
                    .frame(width: 24, height: 24)
                    .background(typeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: .cfRadius4))

                contextLabel
                    .font(.footnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(relativeDate)
                    .font(.caption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }

            // Content / quote
            if let text = primaryText {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(entry.type == .bookmark || entry.type == .highlight
                        ? Color.cfSecondaryLabel
                        : Color.cfLabel
                    )
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: false)
                    .padding(.leading, 32)
            }

            // Tags
            if !entry.effectiveTags.isEmpty {
                tagRow
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, .cfSpacing4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Sub-views

    private var typeIcon: some View {
        Image(systemName: entry.type.systemImage)
    }

    private var contextLabel: some View {
        Group {
            if let bookTitle = entry.bookTitle, let chapterNum = entry.chapterNumber {
                Text("\(bookTitle) · Ch. \(chapterNum)")
            } else if let bookTitle = entry.bookTitle {
                Text(bookTitle)
            } else if let chapterTitle = entry.chapterTitle {
                Text(chapterTitle)
            } else {
                Text(entry.type.displayName)
            }
        }
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .cfSpacing4) {
                ForEach(entry.effectiveTags, id: \.self) { tag in
                    TagChip(tag: tag, isSelected: false)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Derived

    private var primaryText: String? {
        switch entry.type {
        case .note, .reflection, .commitment:
            return entry.content
        case .highlight, .bookmark:
            return entry.quote
        case .unknown:
            return entry.content ?? entry.quote
        }
    }

    private var typeColor: Color {
        switch entry.type {
        case .note:        return .cfAccent
        case .reflection:  return Color(red: 0.55, green: 0.36, blue: 0.80)
        case .bookmark:    return Color(red: 0.85, green: 0.50, blue: 0.15)
        case .commitment:  return Color(red: 0.18, green: 0.65, blue: 0.40)
        case .highlight:   return Color(red: 0.90, green: 0.75, blue: 0.10)
        case .unknown:     return Color.cfSecondaryLabel
        }
    }

    private var relativeDate: String {
        guard let date = rowDateFormatter.date(from: entry.updatedAt)
                      ?? ISO8601DateFormatter().date(from: entry.updatedAt) else {
            return entry.updatedAt
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var accessibilityDescription: String {
        let book = entry.bookTitle.map { " in \($0)" } ?? ""
        let chapter = entry.chapterNumber.map { ", chapter \($0)" } ?? ""
        let text = primaryText.map { ": \($0)" } ?? ""
        return "\(entry.type.displayName)\(book)\(chapter)\(text)"
    }
}

// MARK: - TagChip

/// A small pill chip for a tag label.
struct TagChip: View {
    let tag: String
    let isSelected: Bool

    var body: some View {
        Text(tag)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(isSelected ? Color.cfBackground : Color.cfAccent)
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, .cfSpacing2)
            .background(
                isSelected ? Color.cfAccent : Color.cfAccent.opacity(0.12),
                in: Capsule()
            )
    }
}

// MARK: - ISO8601DateFormatter helper

nonisolated(unsafe) private let rowDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

// MARK: - NotebookEntryType helpers

extension NotebookEntryType {
    var systemImage: String {
        switch self {
        case .note:        return "note.text"
        case .reflection:  return "bubble.left.and.bubble.right"
        case .bookmark:    return "bookmark"
        case .commitment:  return "checkmark.circle"
        case .highlight:   return "highlighter"
        case .unknown:     return "doc.questionmark"
        }
    }

    var displayName: String {
        switch self {
        case .note:        return "Note"
        case .reflection:  return "Reflection"
        case .bookmark:    return "Bookmark"
        case .commitment:  return "Commitment"
        case .highlight:   return "Highlight"
        case .unknown(let s): return s.capitalized
        }
    }
}

// MARK: - Preview

#Preview("Notebook Entry Row", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        ForEach(NotebookEntry.previewEntries) { entry in
            NotebookEntryRowView(entry: entry)
                .padding(.horizontal, .cfSpacing16)
            Divider()
        }
    }
    .background(Color.cfBackground)
}

#Preview("Dark", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        ForEach(NotebookEntry.previewEntries) { entry in
            NotebookEntryRowView(entry: entry)
                .padding(.horizontal, .cfSpacing16)
            Divider()
        }
    }
    .background(Color.cfBackground)
    .preferredColorScheme(.dark)
}
