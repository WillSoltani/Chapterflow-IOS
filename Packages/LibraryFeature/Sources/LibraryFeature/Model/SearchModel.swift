import Foundation
import Observation
import Models
import CoreKit
import Persistence

/// Observable model driving ``GlobalSearchView``.
///
/// Maintains the search index (books + chapter titles), applies debounced
/// client-side filtering, and persists recent searches to `UserDefaults`.
/// Degrades gracefully when offline by searching the cached catalog.
@Observable
@MainActor
public final class SearchModel {

    // MARK: - Nested types

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    public struct BookResult: Identifiable {
        public let book: SearchIndexBook
        public var id: String { book.bookId }
    }

    public struct ChapterResult: Identifiable {
        public let book: SearchIndexBook
        public let chapter: SearchIndexChapter
        public var id: String { chapter.chapterId }
    }

    // MARK: - State

    public private(set) var loadState: LoadState = .idle
    public private(set) var bookResults: [BookResult] = []
    public private(set) var chapterResults: [ChapterResult] = []
    public private(set) var recentSearches: [String] = []
    public private(set) var suggestedCategories: [String] = []
    private var indexBooks: [SearchIndexBook] = []

    // MARK: - Query

    public var rawQuery: String = ""

    /// True while results are being filtered (query is non-empty).
    public var isSearching: Bool {
        !rawQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var hasResults: Bool {
        !bookResults.isEmpty || !chapterResults.isEmpty
    }

    // MARK: - Dependencies

    private let repository: any LibraryRepository
    private let kvStore: KeyValueStore
    private let debouncer: Debouncer

    private static let recentKey = "search.recentQueries.v1"
    private static let maxRecent = 10

    // MARK: - Init

    public init(
        repository: any LibraryRepository,
        kvStore: KeyValueStore = KeyValueStore(),
        debounceInterval: Duration = .milliseconds(300)
    ) {
        self.repository = repository
        self.kvStore = kvStore
        self.debouncer = Debouncer(interval: debounceInterval)
        loadRecentSearches()
    }

    // MARK: - Data loading

    /// Fetches the search index. Falls back to catalog on network failure.
    public func fetch() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let index = try await repository.getSearchIndex()
            indexBooks = index.books
            loadState = .loaded
            updateSuggestedCategories()
            applyQuery(rawQuery)
        } catch {
            // Offline or no cache: fall back to catalog (no chapter search).
            do {
                let catalog = try await repository.getCatalog()
                indexBooks = catalog.map { book in
                    SearchIndexBook(
                        bookId: book.bookId,
                        title: book.title,
                        author: book.author,
                        categories: book.categories,
                        tags: book.tags,
                        cover: book.cover,
                        chapters: []
                    )
                }
                loadState = .loaded
                updateSuggestedCategories()
                applyQuery(rawQuery)
            } catch let appErr as AppError {
                loadState = .error(appErr.errorDescription ?? appErr.code)
            } catch {
                loadState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Query handling (called from view via onChange)

    /// Called by the view whenever `rawQuery` changes. Schedules a debounced filter.
    public func onQueryChanged() {
        debouncer.call { [weak self] in
            guard let self else { return }
            self.applyQuery(self.rawQuery)
        }
    }

    /// Immediately applies the query without debounce (e.g. when tapping a suggestion).
    public func applyQueryNow(_ query: String) {
        rawQuery = query
        applyQuery(query)
    }

    // MARK: - Private filtering

    private func applyQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            bookResults = []
            chapterResults = []
            return
        }
        let lowQ = trimmed.lowercased()
        let books = indexBooks.filter { book in
            book.title.lowercased().contains(lowQ) ||
            book.author.lowercased().contains(lowQ) ||
            book.categories.contains { $0.lowercased().contains(lowQ) } ||
            book.tags.contains { $0.lowercased().contains(lowQ) }
        }
        bookResults = books.map { BookResult(book: $0) }

        let bookMatchIds = Set(books.map { $0.bookId })
        chapterResults = indexBooks.flatMap { book in
            book.chapters
                .filter { $0.title.lowercased().contains(lowQ) }
                .filter { _ in !bookMatchIds.contains(book.bookId) }
                .map { ChapterResult(book: book, chapter: $0) }
        }
    }

    private func updateSuggestedCategories() {
        var freq: [String: Int] = [:]
        for book in indexBooks {
            for cat in book.categories { freq[cat, default: 0] += 1 }
        }
        suggestedCategories = freq
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(8)
            .map { $0.key }
    }

    // MARK: - Recent searches

    /// Commits `query` to the persisted recent-searches list.
    public func commitSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var recent = recentSearches
        recent.removeAll { $0.lowercased() == trimmed.lowercased() }
        recent.insert(trimmed, at: 0)
        if recent.count > Self.maxRecent {
            recent = Array(recent.prefix(Self.maxRecent))
        }
        recentSearches = recent
        saveRecentSearches()
    }

    public func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        saveRecentSearches()
    }

    public func clearRecentSearches() {
        recentSearches = []
        saveRecentSearches()
    }

    private func loadRecentSearches() {
        recentSearches = kvStore.value([String].self, forKey: Self.recentKey) ?? []
    }

    private func saveRecentSearches() {
        try? kvStore.set(recentSearches, forKey: Self.recentKey)
    }
}
