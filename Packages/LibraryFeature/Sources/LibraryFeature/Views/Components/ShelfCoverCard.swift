import SwiftUI
import Models
import DesignSystem

/// A vertical card used inside horizontal shelves on the Discover screen.
///
/// Renders a taller book cover with the title and author beneath it.
/// Tapping calls `onTap`; long-pressing shows a save/open context menu with a
/// rich thumbnail preview. The card is draggable — it exports the book's
/// `chapterflow://book/{id}` URL so it can be dropped into the library list
/// or shared to other apps.
public struct ShelfCoverCard: View {

    let book: BookCatalogItem
    let isSaved: Bool
    let onSave: () -> Void
    let onTap: () -> Void

    public init(
        book: BookCatalogItem,
        isSaved: Bool = false,
        onSave: @escaping () -> Void,
        onTap: @escaping () -> Void
    ) {
        self.book = book
        self.isSaved = isSaved
        self.onSave = onSave
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                BookCoverView(cover: book.cover, size: 104)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: .cfSpacing2) {
                    Text(book.title)
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(book.author)
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .lineLimit(1)
                }
            }
            .frame(width: 110)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("\(book.title) by \(book.author)")
        .contextMenu {
            Button { onTap() } label: {
                Label("Open Book", systemImage: "book.open")
            }
            Button {
                onSave()
            } label: {
                Label(
                    isSaved ? "Remove from Saved" : "Save",
                    systemImage: isSaved ? "bookmark.slash" : "bookmark"
                )
            }
            ShareLink(item: bookURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } preview: {
            contextMenuPreview
        }
        .draggable(bookURL)
    }

    // MARK: - Context menu preview

    private var contextMenuPreview: some View {
        VStack(spacing: .cfSpacing8) {
            BookCoverView(cover: book.cover, size: 120)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            VStack(spacing: .cfSpacing4) {
                Text(book.title)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                    .multilineTextAlignment(.center)
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
}

// MARK: - Previews

#if DEBUG
#Preview("Shelf cover card", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        ShelfCoverCard(
            book: PreviewData.atomicHabits,
            isSaved: true,
            onSave: {},
            onTap: {}
        )
        ShelfCoverCard(
            book: PreviewData.deepWork,
            isSaved: false,
            onSave: {},
            onTap: {}
        )
    }
    .padding()
}

#Preview("Dark mode", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        ShelfCoverCard(book: PreviewData.atomicHabits, onSave: {}, onTap: {})
        ShelfCoverCard(book: PreviewData.deepWork, onSave: {}, onTap: {})
    }
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("XXL type", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        ShelfCoverCard(book: PreviewData.atomicHabits, onSave: {}, onTap: {})
        ShelfCoverCard(book: PreviewData.deepWork, onSave: {}, onTap: {})
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
}
#endif
