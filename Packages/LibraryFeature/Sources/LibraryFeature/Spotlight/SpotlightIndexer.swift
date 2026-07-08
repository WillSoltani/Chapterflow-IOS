import CoreSpotlight
import Models
import CoreKit

#if canImport(UIKit)
import UIKit
#endif

/// Indexes books and chapters into Core Spotlight so they surface in system search.
///
/// Design:
/// - `uniqueIdentifier` for each `CSSearchableItem` is a `chapterflow://` deep-link
///   URL, so tapping the Spotlight result routes through `DeepLink(url:)`.
/// - `domainIdentifier` groups chapters under their book for bulk delete.
/// - All operations run off the main thread (actor isolation).
/// - Indexing is idempotent: re-submitting an existing identifier updates the item.
/// - `removeAll()` clears the index on sign-out to honour auth state.
public actor SpotlightIndexer {

    private static let log = AppLog(category: "spotlight")

    public init() {}

    // MARK: - Public API

    /// Indexes books and their chapters into Spotlight.
    ///
    /// - Parameters:
    ///   - books: The full catalog; each book produces one searchable item.
    ///   - searchBooks: Chapter-level index; each chapter produces one searchable item
    ///     grouped under its parent book's `domainIdentifier`.
    public func index(books: [BookCatalogItem], searchBooks: [SearchIndexBook]) async {
        let items = Self.buildItems(books: books, searchBooks: searchBooks)
        guard !items.isEmpty else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    Self.log.error("Spotlight index failed: \(error.localizedDescription)")
                }
                cont.resume()
            }
        }
    }

    /// Removes all ChapterFlow Spotlight items. Call on sign-out.
    public func removeAll() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            CSSearchableIndex.default().deleteAllSearchableItems { error in
                if let error {
                    Self.log.error("Spotlight removeAll failed: \(error.localizedDescription)")
                }
                cont.resume()
            }
        }
    }

    // MARK: - Item construction (internal for testing)

    /// Builds `CSSearchableItem`s for the given books and their chapters.
    ///
    /// This is a static (nonisolated) function so unit tests can verify item
    /// shape without spinning up a real `CSSearchableIndex`.
    static func buildItems(
        books: [BookCatalogItem],
        searchBooks: [SearchIndexBook]
    ) -> [CSSearchableItem] {
        var items: [CSSearchableItem] = []

        for book in books {
            let domain = domainIdentifier(bookId: book.bookId)

            // One item per book
            let bookItem = CSSearchableItem(
                uniqueIdentifier: bookURL(bookId: book.bookId),
                domainIdentifier: domain,
                attributeSet: makeBookAttributes(book: book)
            )
            bookItem.expirationDate = .distantFuture
            items.append(bookItem)

            // One item per chapter when a search-index entry exists for this book
            if let searchBook = searchBooks.first(where: { $0.bookId == book.bookId }) {
                for chapter in searchBook.chapters {
                    let chapterItem = CSSearchableItem(
                        uniqueIdentifier: chapterURL(bookId: book.bookId, number: chapter.number),
                        domainIdentifier: domain,
                        attributeSet: makeChapterAttributes(chapter: chapter, book: book)
                    )
                    chapterItem.expirationDate = .distantFuture
                    items.append(chapterItem)
                }
            }
        }
        return items
    }

    // MARK: - URL helpers (internal for testing)

    static func bookURL(bookId: String) -> String {
        "chapterflow://book/\(bookId)"
    }

    static func chapterURL(bookId: String, number: Int) -> String {
        "chapterflow://book/\(bookId)/chapter/\(number)"
    }

    static func domainIdentifier(bookId: String) -> String {
        "com.chapterflow.book.\(bookId)"
    }

    // MARK: - Attribute builders

    private static func makeBookAttributes(book: BookCatalogItem) -> CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)
        attrs.title = book.title
        attrs.contentDescription = "by \(book.author)"
        attrs.keywords = book.categories + book.tags + [book.author]
        #if canImport(UIKit)
        attrs.thumbnailData = renderThumbnail(
            emoji: book.cover?.emoji,
            hexColor: book.cover?.color
        )
        #endif
        return attrs
    }

    private static func makeChapterAttributes(
        chapter: SearchIndexChapter,
        book: BookCatalogItem
    ) -> CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)
        attrs.title = chapter.title
        attrs.contentDescription = "\(book.title) · Chapter \(chapter.number) · by \(book.author)"
        attrs.keywords = [book.title, book.author] + book.categories
        #if canImport(UIKit)
        attrs.thumbnailData = renderThumbnail(
            emoji: book.cover?.emoji,
            hexColor: book.cover?.color
        )
        #endif
        return attrs
    }

    // MARK: - Thumbnail rendering

    #if canImport(UIKit)
    /// Renders the book's emoji + color as a PNG thumbnail for Spotlight.
    ///
    /// `UIGraphicsImageRenderer` is thread-safe since iOS 10, so it's safe to
    /// call from a background actor without dispatching to the main thread.
    private static func renderThumbnail(emoji: String?, hexColor: String?) -> Data? {
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let color = UIColor(hex: hexColor) ?? .systemGray5
            color.setFill()
            UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: 16
            ).fill()

            let em = emoji ?? "📖"
            let font = UIFont.systemFont(ofSize: 60)
            let strAttrs: [NSAttributedString.Key: Any] = [.font: font]
            let str = NSAttributedString(string: em, attributes: strAttrs)
            let strSize = str.size()
            str.draw(at: CGPoint(
                x: (size.width - strSize.width) / 2,
                y: (size.height - strSize.height) / 2
            ))
        }
        return image.pngData()
    }
    #endif
}

// MARK: - UIColor + hex

#if canImport(UIKit)
private extension UIColor {
    convenience init?(hex: String?) {
        guard let hex else { return nil }
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6, let value = UInt64(str, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >>  8) & 0xFF) / 255,
            blue:  CGFloat((value      ) & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
