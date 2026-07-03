import SwiftUI
import Models
import DesignSystem

/// A vertical card used inside horizontal shelves on the Discover screen.
///
/// Renders a taller book cover with the title and author beneath it.
/// Tapping calls `onTap`; long-pressing shows a save/open context menu.
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
            Button {
                onSave()
            } label: {
                Label(
                    isSaved ? "Remove from Saved" : "Save",
                    systemImage: isSaved ? "bookmark.slash" : "bookmark"
                )
            }
            Button { onTap() } label: {
                Label("Open Book", systemImage: "book")
            }
        }
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
#endif
