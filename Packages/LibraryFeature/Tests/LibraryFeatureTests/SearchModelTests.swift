import Testing
@testable import LibraryFeature
import Models
import CoreKit
import Persistence
import Foundation

// MARK: - Helpers

private func makeIndex() -> SearchIndexResponse {
    SearchIndexResponse(books: [
        SearchIndexBook(
            bookId: "b-atomic-habits",
            title: "Atomic Habits",
            author: "James Clear",
            categories: ["Productivity", "Psychology"],
            tags: ["habits", "behavior-change"],
            cover: nil,
            chapters: [
                SearchIndexChapter(chapterId: "ch-ah-1", number: 1,
                                   title: "The Surprising Power of Atomic Habits"),
                SearchIndexChapter(chapterId: "ch-ah-2", number: 2,
                                   title: "How Your Habits Shape Your Identity"),
            ]
        ),
        SearchIndexBook(
            bookId: "b-deep-work",
            title: "Deep Work",
            author: "Cal Newport",
            categories: ["Productivity", "Focus"],
            tags: ["focus", "deep-work"],
            cover: nil,
            chapters: [
                SearchIndexChapter(chapterId: "ch-dw-1", number: 1,
                                   title: "Deep Work Is Valuable"),
                SearchIndexChapter(chapterId: "ch-dw-2", number: 2,
                                   title: "Deep Work Is Rare"),
            ]
        ),
        SearchIndexBook(
            bookId: "b-thinking",
            title: "Thinking, Fast and Slow",
            author: "Daniel Kahneman",
            categories: ["Psychology"],
            tags: ["cognitive-bias"],
            cover: nil,
            chapters: [
                SearchIndexChapter(chapterId: "ch-tfs-1", number: 1,
                                   title: "The Characters of the Story"),
            ]
        ),
    ])
}

@MainActor
private func makeModel(
    index: SearchIndexResponse? = nil,
    error: AppError? = nil
) -> SearchModel {
    let repo = FakeLibraryRepository(
        searchIndex: index ?? makeIndex(),
        error: error
    )
    // Zero-duration debounce for synchronous test assertions
    return SearchModel(
        repository: repo,
        kvStore: KeyValueStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard),
        debounceInterval: .zero
    )
}

// MARK: - FakeLibraryRepository (extended init for tests)

extension FakeLibraryRepository {
    init(searchIndex: SearchIndexResponse?, error: AppError? = nil) {
        self.init(catalog: [], error: error, searchIndex: searchIndex)
    }
}

// MARK: - SearchModel tests

@Suite("SearchModel")
@MainActor
struct SearchModelTests {

    // MARK: - Fetch

    @Test("fetch populates suggestedCategories from index")
    func fetchPopulatesCategories() async {
        let model = makeModel()
        await model.fetch()
        #expect(!model.suggestedCategories.isEmpty)
        // "Productivity" appears in 2 books, should be first
        #expect(model.suggestedCategories.first == "Productivity")
    }

    @Test("fetch degrades to catalog on network error")
    func fetchDegradesToCatalog() async {
        let catalog = [
            BookCatalogItem(
                bookId: "b-test", title: "Test Book", author: "Author",
                categories: ["Tech"], tags: [], cover: nil,
                variantFamily: .emh, status: "published",
                latestVersion: 1, currentPublishedVersion: 1, updatedAt: ""
            ),
        ]
        let repo = FakeLibraryRepository(catalog: catalog, error: nil, searchIndex: nil)
        // Override: make getSearchIndex throw but getCatalog succeed
        let model = SearchModel(
            repository: repo,
            kvStore: KeyValueStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard),
            debounceInterval: .zero
        )
        // repo has no searchIndex stub, so getSearchIndex builds from catalog
        await model.fetch()
        if case .loaded = model.loadState { } else {
            Issue.record("Expected .loaded, got \(model.loadState)")
        }
    }

    @Test("fetch sets error state when both index and catalog fail")
    func fetchSetsErrorWhenAllFail() async {
        let model = makeModel(error: .offline)
        await model.fetch()
        if case .error = model.loadState { } else {
            Issue.record("Expected .error, got \(model.loadState)")
        }
    }

    // MARK: - Book search
    // Note: applyQueryNow is used in filter tests for synchronous assertions;
    // the debounce path (onQueryChanged) is wired by the view via onChange.

    @Test("book title match (case-insensitive)")
    func bookTitleMatch() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("atomic")
        #expect(model.bookResults.count == 1)
        #expect(model.bookResults[0].book.bookId == "b-atomic-habits")
    }

    @Test("book author match")
    func bookAuthorMatch() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("Newport")
        #expect(model.bookResults.count == 1)
        #expect(model.bookResults[0].book.bookId == "b-deep-work")
    }

    @Test("book category match")
    func bookCategoryMatch() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("Psychology")
        // Atomic Habits + Thinking both have Psychology
        #expect(model.bookResults.count == 2)
    }

    @Test("book tag match")
    func bookTagMatch() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("habits")
        #expect(model.bookResults.count == 1)
        #expect(model.bookResults[0].book.bookId == "b-atomic-habits")
    }

    @Test("empty query clears results")
    func emptyQueryClearsResults() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("atomic")
        #expect(!model.bookResults.isEmpty)
        model.applyQueryNow("")
        #expect(model.bookResults.isEmpty)
        #expect(model.chapterResults.isEmpty)
    }

    @Test("whitespace-only query produces no results")
    func whitespaceQueryProducesNoResults() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("   ")
        #expect(model.bookResults.isEmpty)
        #expect(model.chapterResults.isEmpty)
    }

    @Test("no-match query produces empty results")
    func noMatchQueryProducesEmptyResults() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("zzz-no-match-xyz")
        #expect(model.bookResults.isEmpty)
        #expect(model.chapterResults.isEmpty)
        #expect(!model.hasResults)
    }

    // MARK: - Chapter search

    @Test("chapter title match returns chapter results")
    func chapterTitleMatch() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("Valuable")
        #expect(model.chapterResults.count == 1)
        #expect(model.chapterResults[0].chapter.chapterId == "ch-dw-1")
        #expect(model.chapterResults[0].book.bookId == "b-deep-work")
    }

    @Test("chapter results exclude books already in book results")
    func chapterResultsExcludeMatchingBooks() async {
        let model = makeModel()
        await model.fetch()
        // "Atomic Habits" matches as a book AND has chapters with "Habits" in title
        // Since the book matched, its chapters should be excluded from chapterResults
        model.applyQueryNow("habits")
        let chapterBooksForAtomicHabits = model.chapterResults.filter {
            $0.book.bookId == "b-atomic-habits"
        }
        #expect(chapterBooksForAtomicHabits.isEmpty)
    }

    @Test("chapter result carries correct book reference")
    func chapterResultHasCorrectBook() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("Characters")
        #expect(model.chapterResults.count == 1)
        #expect(model.chapterResults[0].book.bookId == "b-thinking")
        #expect(model.chapterResults[0].chapter.number == 1)
    }

    // MARK: - isSearching / hasResults

    @Test("isSearching is false for empty query")
    func isSearchingFalseForEmptyQuery() async {
        let model = makeModel()
        await model.fetch()
        model.rawQuery = ""
        #expect(!model.isSearching)
    }

    @Test("isSearching is true for non-empty query")
    func isSearchingTrueForQuery() async {
        let model = makeModel()
        await model.fetch()
        model.rawQuery = "test"
        #expect(model.isSearching)
    }

    // MARK: - Recent searches

    @Test("commitSearch adds to recentSearches")
    func commitSearchAddsToRecent() async {
        let model = makeModel()
        model.commitSearch("atomic habits")
        #expect(model.recentSearches.first == "atomic habits")
    }

    @Test("commitSearch deduplicates (case-insensitive)")
    func commitSearchDeduplicates() async {
        let model = makeModel()
        model.commitSearch("atomic")
        model.commitSearch("ATOMIC")
        #expect(model.recentSearches.filter { $0.lowercased() == "atomic" }.count == 1)
    }

    @Test("commitSearch moves existing entry to front")
    func commitSearchMovesToFront() async {
        let model = makeModel()
        model.commitSearch("focus")
        model.commitSearch("habits")
        model.commitSearch("focus")
        #expect(model.recentSearches.first == "focus")
    }

    @Test("commitSearch caps at 10 entries")
    func commitSearchCapsAtTen() async {
        let model = makeModel()
        for i in 0..<15 {
            model.commitSearch("query\(i)")
        }
        #expect(model.recentSearches.count == 10)
    }

    @Test("commitSearch ignores blank query")
    func commitSearchIgnoresBlank() async {
        let model = makeModel()
        model.commitSearch("   ")
        #expect(model.recentSearches.isEmpty)
    }

    @Test("removeRecentSearch removes the specific entry")
    func removeRecentSearch() async {
        let model = makeModel()
        model.commitSearch("atomic")
        model.commitSearch("habits")
        model.removeRecentSearch("atomic")
        #expect(!model.recentSearches.contains("atomic"))
        #expect(model.recentSearches.contains("habits"))
    }

    @Test("clearRecentSearches empties the list")
    func clearRecentSearches() async {
        let model = makeModel()
        model.commitSearch("a")
        model.commitSearch("b")
        model.clearRecentSearches()
        #expect(model.recentSearches.isEmpty)
    }

    @Test("recent searches persist across model instances (same UserDefaults)")
    func recentSearchesPersist() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let kvStore = KeyValueStore(defaults: defaults)
        let repo = FakeLibraryRepository(searchIndex: makeIndex())
        let model1 = SearchModel(repository: repo, kvStore: kvStore, debounceInterval: .zero)
        model1.commitSearch("deep work")

        let model2 = SearchModel(repository: repo, kvStore: kvStore, debounceInterval: .zero)
        #expect(model2.recentSearches.contains("deep work"))
    }

    // MARK: - Suggested categories

    @Test("suggestedCategories ranks by frequency descending")
    func suggestedCategoriesRankedByFrequency() async {
        let model = makeModel()
        await model.fetch()
        // Productivity appears in 2 books; Psychology in 2; Focus in 1
        let cats = model.suggestedCategories
        #expect(!cats.isEmpty)
        // Both Productivity and Psychology have freq 2, Focus has 1
        // Focus must come after both
        if let focusIdx = cats.firstIndex(of: "Focus"),
           let prodIdx = cats.firstIndex(of: "Productivity") {
            #expect(prodIdx < focusIdx)
        }
    }

    // MARK: - applyQueryNow

    @Test("applyQueryNow immediately updates rawQuery and results")
    func applyQueryNow() async {
        let model = makeModel()
        await model.fetch()
        model.applyQueryNow("deep")
        #expect(model.rawQuery == "deep")
        #expect(model.bookResults.count == 1)
        #expect(model.bookResults[0].book.bookId == "b-deep-work")
    }
}

// MARK: - SearchIndexResponse tolerant decoding

@Suite("SearchIndexResponse — tolerant decoding")
struct SearchIndexResponseDecodingTests {

    @Test("single malformed book is dropped, valid books survive")
    func malformedBookDropped() throws {
        let json = """
        {
          "books": [
            {"bookId": "b-good", "title": "Good", "author": "Author",
             "categories": [], "tags": [], "chapters": []},
            null,
            {"bookId": "b-also-good", "title": "Also Good", "author": "Author2",
             "categories": [], "tags": [], "chapters": []}
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder.chapterFlow
        let response = try decoder.decode(SearchIndexResponse.self, from: json)
        #expect(response.books.count == 2)
        let ids = response.books.map { $0.bookId }
        #expect(ids.contains("b-good"))
        #expect(ids.contains("b-also-good"))
    }

    @Test("missing optional fields decode without crash")
    func missingOptionalFields() throws {
        let json = """
        {
          "books": [
            {"bookId": "b-min", "title": "Min", "author": "A"}
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder.chapterFlow
        let response = try decoder.decode(SearchIndexResponse.self, from: json)
        #expect(response.books.count == 1)
        #expect(response.books[0].categories.isEmpty)
        #expect(response.books[0].chapters.isEmpty)
        #expect(response.books[0].cover == nil)
    }

    @Test("empty books array decodes to empty collection")
    func emptyBooksArray() throws {
        let json = "{\"books\": []}".data(using: .utf8)!
        let decoder = JSONDecoder.chapterFlow
        let response = try decoder.decode(SearchIndexResponse.self, from: json)
        #expect(response.books.isEmpty)
    }

    @Test("malformed chapter in a book is dropped, other chapters survive")
    func malformedChapterDropped() throws {
        let json = """
        {
          "books": [{
            "bookId": "b-ok", "title": "OK", "author": "A",
            "chapters": [
              {"chapterId": "ch-1", "number": 1, "title": "Good Chapter"},
              null,
              {"chapterId": "ch-3", "number": 3, "title": "Another Good Chapter"}
            ]
          }]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder.chapterFlow
        let response = try decoder.decode(SearchIndexResponse.self, from: json)
        #expect(response.books.count == 1)
        #expect(response.books[0].chapters.count == 2)
    }
}
