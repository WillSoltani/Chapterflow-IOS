import SwiftUI
import Models
import DesignSystem

/// A titled horizontal scroll shelf of ``ShelfCoverCard`` items.
///
/// Used on the Discover screen for curated shelves (New, Popular, For You, etc.)
/// An optional "See All" action appears in the header when provided.
public struct BookShelfView: View {

    let title: String
    let books: [BookCatalogItem]
    let savedBookIds: Set<String>
    let onSeeAll: (() -> Void)?
    let onToggleSaved: (String) -> Void
    let onBookTapped: (String) -> Void

    public init(
        title: String,
        books: [BookCatalogItem],
        savedBookIds: Set<String> = [],
        onSeeAll: (() -> Void)? = nil,
        onToggleSaved: @escaping (String) -> Void,
        onBookTapped: @escaping (String) -> Void
    ) {
        self.title = title
        self.books = books
        self.savedBookIds = savedBookIds
        self.onSeeAll = onSeeAll
        self.onToggleSaved = onToggleSaved
        self.onBookTapped = onBookTapped
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            shelfHeader
            booksScroll
        }
    }

    // MARK: - Header

    private var shelfHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)

            Spacer()

            if let onSeeAll {
                Button("See All", action: onSeeAll)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfAccent)
                    .accessibilityLabel("See all \(title) books")
            }
        }
        .padding(.horizontal, .cfSpacing16)
    }

    // MARK: - Books

    private var booksScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: .cfSpacing12) {
                ForEach(books) { book in
                    ShelfCoverCard(
                        book: book,
                        isSaved: savedBookIds.contains(book.bookId),
                        onSave: { onToggleSaved(book.bookId) },
                        onTap: { onBookTapped(book.bookId) }
                    )
                }
            }
            .padding(.horizontal, .cfSpacing16)
        }
    }
}

// MARK: - Skeleton

/// Shimmer placeholder that matches the height of a ``BookShelfView``.
struct BookShelfSkeleton: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            // Header placeholder
            RoundedRectangle(cornerRadius: .cfRadius4, style: .continuous)
                .fill(shimmerFill)
                .frame(width: 120, height: 18)
                .padding(.horizontal, .cfSpacing16)

            // Card row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .cfSpacing12) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: .cfSpacing8) {
                            RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous)
                                .fill(shimmerFill)
                                .frame(width: 110, height: 154) // cover aspect
                            RoundedRectangle(cornerRadius: .cfRadius4, style: .continuous)
                                .fill(shimmerFill)
                                .frame(width: 90, height: 12)
                            RoundedRectangle(cornerRadius: .cfRadius4, style: .continuous)
                                .fill(shimmerFill)
                                .frame(width: 60, height: 10)
                        }
                        .frame(width: 110)
                    }
                }
                .padding(.horizontal, .cfSpacing16)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityLabel("Loading")
        .accessibilityHidden(true)
    }

    private var shimmerFill: some ShapeStyle {
        if reduceMotion {
            return AnyShapeStyle(Color.cfSecondaryFill)
        }
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: Color.cfSecondaryFill,      location: max(0, phase - 0.3)),
                    .init(color: Color.cfTertiaryBackground, location: phase),
                    .init(color: Color.cfSecondaryFill,      location: min(1, phase + 0.3)),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Book shelf", traits: .sizeThatFitsLayout) {
    BookShelfView(
        title: "New & Updated",
        books: PreviewData.books,
        savedBookIds: ["b-deep-work"],
        onSeeAll: {},
        onToggleSaved: { _ in },
        onBookTapped: { _ in }
    )
    .padding(.vertical)
}

#Preview("Shelf skeleton", traits: .sizeThatFitsLayout) {
    BookShelfSkeleton()
        .padding(.vertical)
}
#endif
