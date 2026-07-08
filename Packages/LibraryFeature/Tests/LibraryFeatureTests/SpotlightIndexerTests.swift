import Testing
import Foundation
@testable import LibraryFeature
import Models
import CoreKit
import Fixtures

// MARK: - URL helpers

@Suite("SpotlightIndexer URL helpers")
struct SpotlightURLTests {

    @Test("bookURL produces chapterflow://book/{id}")
    func bookURLFormat() {
        let url = SpotlightIndexer.bookURL(bookId: "b-atomic-habits")
        #expect(url == "chapterflow://book/b-atomic-habits")
    }

    @Test("chapterURL produces chapterflow://book/{id}/chapter/{n}")
    func chapterURLFormat() {
        let url = SpotlightIndexer.chapterURL(bookId: "b-deep-work", number: 3)
        #expect(url == "chapterflow://book/b-deep-work/chapter/3")
    }

    @Test("domainIdentifier groups by book")
    func domainIdentifierFormat() {
        let domain = SpotlightIndexer.domainIdentifier(bookId: "b-thinking")
        #expect(domain == "com.chapterflow.book.b-thinking")
    }

    @Test("bookURL is parseable by DeepLink")
    func bookURLParsesAsDeepLink() throws {
        let urlStr = SpotlightIndexer.bookURL(bookId: "b-atomic-habits")
        let url = try #require(URL(string: urlStr))
        let link = try #require(DeepLink(url: url))
        if case .book(let id) = link {
            #expect(id == "b-atomic-habits")
        } else {
            Issue.record("Expected .book deep link, got \(link)")
        }
    }

    @Test("chapterURL is parseable by DeepLink")
    func chapterURLParsesAsDeepLink() throws {
        let urlStr = SpotlightIndexer.chapterURL(bookId: "b-atomic-habits", number: 2)
        let url = try #require(URL(string: urlStr))
        let link = try #require(DeepLink(url: url))
        if case .chapter(let bookId, let number) = link {
            #expect(bookId == "b-atomic-habits")
            #expect(number == 2)
        } else {
            Issue.record("Expected .chapter deep link, got \(link)")
        }
    }
}

// MARK: - Item building

@Suite("SpotlightIndexer.buildItems")
struct SpotlightBuildItemsTests {

    private static let sampleBooks: [BookCatalogItem] = Fixtures.books

    private static func makeSearchBook(
        bookId: String,
        title: String,
        author: String,
        chapterCount: Int
    ) -> SearchIndexBook {
        let chapters = (1...max(1, chapterCount)).map { n in
            SearchIndexChapter(chapterId: "\(bookId)-ch\(n)", number: n, title: "Chapter \(n) Title")
        }
        return SearchIndexBook(
            bookId: bookId,
            title: title,
            author: author,
            categories: ["Test"],
            tags: [],
            cover: nil,
            chapters: chapters
        )
    }

    @Test("no books → no items")
    func emptyBooksProducesNoItems() {
        let items = SpotlightIndexer.buildItems(books: [], searchBooks: [])
        #expect(items.isEmpty)
    }

    @Test("book with no search-index entry produces one item")
    func bookWithNoChaptersProducesOneItem() {
        let books = [Fixtures.atomicHabits]
        let items = SpotlightIndexer.buildItems(books: books, searchBooks: [])
        #expect(items.count == 1)
        #expect(items[0].uniqueIdentifier == SpotlightIndexer.bookURL(bookId: "b-atomic-habits"))
    }

    @Test("book with N chapters produces 1 + N items")
    func bookWithChaptersProducesCorrectCount() {
        let searchBook = Self.makeSearchBook(
            bookId: "b-atomic-habits",
            title: "Atomic Habits",
            author: "James Clear",
            chapterCount: 5
        )
        let items = SpotlightIndexer.buildItems(
            books: [Fixtures.atomicHabits],
            searchBooks: [searchBook]
        )
        #expect(items.count == 6) // 1 book + 5 chapters
    }

    @Test("three books each with 3 chapters produces 3 + 9 = 12 items")
    func multipleBooks() {
        let books = Self.sampleBooks
        let searchBooks = books.map { book in
            Self.makeSearchBook(
                bookId: book.bookId,
                title: book.title,
                author: book.author,
                chapterCount: 3
            )
        }
        let items = SpotlightIndexer.buildItems(books: books, searchBooks: searchBooks)
        #expect(items.count == 12)
    }

    @Test("each book item has the correct uniqueIdentifier")
    func bookItemHasCorrectURL() {
        let books = Self.sampleBooks
        let items = SpotlightIndexer.buildItems(books: books, searchBooks: [])
        let bookURLs = items.map(\.uniqueIdentifier)
        for book in books {
            #expect(bookURLs.contains(SpotlightIndexer.bookURL(bookId: book.bookId)))
        }
    }

    @Test("chapter items use chapterflow://book/{id}/chapter/{n}")
    func chapterItemHasCorrectURL() {
        let searchBook = Self.makeSearchBook(
            bookId: "b-deep-work",
            title: "Deep Work",
            author: "Cal Newport",
            chapterCount: 3
        )
        let items = SpotlightIndexer.buildItems(
            books: [Fixtures.deepWork],
            searchBooks: [searchBook]
        )
        let chapterItems = items.filter { $0.uniqueIdentifier.contains("/chapter/") }
        #expect(chapterItems.count == 3)
        for (idx, item) in chapterItems.enumerated() {
            let expected = SpotlightIndexer.chapterURL(bookId: "b-deep-work", number: idx + 1)
            #expect(item.uniqueIdentifier == expected)
        }
    }

    @Test("all items for a book share the same domainIdentifier")
    func itemsShareDomainIdentifier() {
        let searchBook = Self.makeSearchBook(
            bookId: "b-atomic-habits",
            title: "Atomic Habits",
            author: "James Clear",
            chapterCount: 3
        )
        let items = SpotlightIndexer.buildItems(
            books: [Fixtures.atomicHabits],
            searchBooks: [searchBook]
        )
        let expected = SpotlightIndexer.domainIdentifier(bookId: "b-atomic-habits")
        for item in items {
            #expect(item.domainIdentifier == expected)
        }
    }

    @Test("book item title matches book title")
    func bookItemTitle() {
        let items = SpotlightIndexer.buildItems(
            books: [Fixtures.atomicHabits],
            searchBooks: []
        )
        #expect(items[0].attributeSet.title == "Atomic Habits")
    }

    @Test("chapter item title matches chapter title from search index")
    func chapterItemTitle() {
        let searchBook = Self.makeSearchBook(
            bookId: "b-atomic-habits",
            title: "Atomic Habits",
            author: "James Clear",
            chapterCount: 1
        )
        let items = SpotlightIndexer.buildItems(
            books: [Fixtures.atomicHabits],
            searchBooks: [searchBook]
        )
        let chapterItem = items.first { $0.uniqueIdentifier.contains("/chapter/") }
        #expect(chapterItem?.attributeSet.title == "Chapter 1 Title")
    }

    @Test("items do not expire (expirationDate is distantFuture)")
    func itemsDoNotExpire() {
        let items = SpotlightIndexer.buildItems(books: [Fixtures.atomicHabits], searchBooks: [])
        #expect(items[0].expirationDate == .distantFuture)
    }

    @Test("search-index entries for other books do not bleed into unrelated books")
    func isolationBetweenBooks() {
        let deepWorkSearchBook = Self.makeSearchBook(
            bookId: "b-deep-work",
            title: "Deep Work",
            author: "Cal Newport",
            chapterCount: 4
        )
        // Only Atomic Habits in the catalog
        let items = SpotlightIndexer.buildItems(
            books: [Fixtures.atomicHabits],
            searchBooks: [deepWorkSearchBook]
        )
        // Deep Work chapters should NOT appear — no catalog entry for them
        #expect(items.count == 1)
        #expect(items[0].uniqueIdentifier == SpotlightIndexer.bookURL(bookId: "b-atomic-habits"))
    }
}
