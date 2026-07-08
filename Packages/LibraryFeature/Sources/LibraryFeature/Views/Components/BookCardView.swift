import SwiftUI
import Models
import DesignSystem

/// A horizontal book card showing the cover, title, author, and optional progress.
///
/// Used in list rows across HomeView and LibraryView. The `onSave` closure
/// fires when the user taps the bookmark icon or triggers the context-menu save
/// action. Pass `nil` for `onSave` to hide the bookmark affordance.
///
/// **P8.6 additions:** rich context-menu preview thumbnail, ShareLink, drag
/// (`chapterflow://book/{id}` URL), and drop support (drops any chapterflow
/// book URL and calls `onSave` to save this card's book).
public struct BookCardView: View {

    let book: BookCatalogItem
    let progress: ProgressOverviewItem?
    let isSaved: Bool
    let onSave: (() -> Void)?
    let onTap: (() -> Void)?

    public init(
        book: BookCatalogItem,
        progress: ProgressOverviewItem? = nil,
        isSaved: Bool = false,
        onSave: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.book = book
        self.progress = progress
        self.isSaved = isSaved
        self.onSave = onSave
        self.onTap = onTap
    }

    public var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: .cfSpacing12) {
                BookCoverView(cover: book.cover, size: 56)

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(book.title)
                        .font(.cfHeadline)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(2)

                    Text(book.author)
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .lineLimit(1)

                    if let p = progress {
                        progressRow(p)
                    } else {
                        categoryRow
                    }
                }

                Spacer(minLength: 0)

                if let onSave {
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isSaved ? Color.cfAccent : Color.cfTertiaryLabel)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSaved ? "Remove from saved" : "Save book")
                }
            }
            .padding(.vertical, .cfSpacing8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .contextMenu {
            contextMenuItems
        } preview: {
            contextMenuPreview
        }
        .draggable(bookURL)
        .dropDestination(for: URL.self) { urls, _ in
            guard let onSave, !isSaved else { return false }
            let isBookURL = urls.contains {
                $0.scheme?.lowercased() == "chapterflow" && $0.host?.lowercased() == "book"
            }
            guard isBookURL else { return false }
            onSave()
            return true
        }
    }

    // MARK: - Subviews

    private func progressRow(_ p: ProgressOverviewItem) -> some View {
        HStack(spacing: .cfSpacing4) {
            ProgressRingView(progress: p.completionFraction, size: 16, lineWidth: 2)
            Text("\(p.completedChapterCount) of \(p.totalChapters) ch.")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
    }

    private var categoryRow: some View {
        Text(book.categories.prefix(2).joined(separator: " · "))
            .font(.cfCaption)
            .foregroundStyle(Color.cfTertiaryLabel)
            .lineLimit(1)
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            onTap?()
        } label: {
            Label("Open Book", systemImage: "book.open")
        }
        if let onSave {
            Button {
                onSave()
            } label: {
                Label(
                    isSaved ? "Remove from Saved" : "Save",
                    systemImage: isSaved ? "bookmark.slash" : "bookmark"
                )
            }
        }
        ShareLink(item: bookURL) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            let text = "\(book.title) by \(book.author)"
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #endif
        } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }
    }

    /// Rich thumbnail shown while the context menu is open.
    private var contextMenuPreview: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            BookCoverView(cover: book.cover, size: 120)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(book.title)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                    .lineLimit(2)
                Text(book.author)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .lineLimit(1)
            }
        }
        .padding(.cfSpacing16)
        .frame(width: 200)
        .background(Color.cfBackground)
    }

    // MARK: - Helpers

    private var bookURL: URL {
        URL(string: "chapterflow://book/\(book.bookId)") ?? URL(string: "chapterflow://library")!
    }

    private var accessibilityLabel: String {
        var parts = [book.title, "by \(book.author)"]
        if let p = progress {
            parts.append("\(p.completedChapterCount) of \(p.totalChapters) chapters complete")
        }
        if isSaved { parts.append("Saved") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Book card — with progress", traits: .sizeThatFitsLayout) {
    BookCardView(
        book: PreviewData.atomicHabits,
        progress: PreviewData.atomicHabitsProgress,
        isSaved: true,
        onSave: {}
    )
    .padding(.horizontal, 16)
}

#Preview("Book card — dark", traits: .sizeThatFitsLayout) {
    BookCardView(
        book: PreviewData.deepWork,
        isSaved: false,
        onSave: {}
    )
    .padding(.horizontal, 16)
    .preferredColorScheme(.dark)
}

#Preview("Book card — XXL type", traits: .sizeThatFitsLayout) {
    BookCardView(
        book: PreviewData.atomicHabits,
        progress: PreviewData.atomicHabitsProgress,
        isSaved: true,
        onSave: {}
    )
    .padding(.horizontal, 16)
    .dynamicTypeSize(.accessibility3)
}
#endif
