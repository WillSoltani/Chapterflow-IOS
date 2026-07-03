import Models
import CoreKit

/// In-memory ``LibraryRepository`` for unit tests and SwiftUI previews.
///
/// Seed it with fixture data and inject it into models, then observe which IDs
/// end up in `toggleSaved`. An optional `error` forces every method to throw.
public actor FakeLibraryRepository: LibraryRepository {

    private var catalogStub: [BookCatalogItem]
    private var progressStub: ProgressOverviewResponse
    private var savedStub: [String]
    private let forcedError: AppError?
    private let searchIndexStub: SearchIndexResponse?

    public init(
        catalog: [BookCatalogItem] = [],
        progress: ProgressOverviewResponse = ProgressOverviewResponse(progress: []),
        savedBookIds: [String] = [],
        error: AppError? = nil,
        searchIndex: SearchIndexResponse? = nil
    ) {
        self.catalogStub = catalog
        self.progressStub = progress
        self.savedStub = savedBookIds
        self.forcedError = error
        self.searchIndexStub = searchIndex
    }

    // MARK: - LibraryRepository

    public func getCatalog() async throws -> [BookCatalogItem] {
        if let e = forcedError { throw e }
        return catalogStub
    }

    public func getProgressOverview() async throws -> ProgressOverviewResponse {
        if let e = forcedError { throw e }
        return progressStub
    }

    public func getSaved() async throws -> [String] {
        if let e = forcedError { throw e }
        return savedStub
    }

    public func toggleSaved(bookId: String, saved: Bool) async throws -> [String] {
        if let e = forcedError { throw e }
        if saved {
            if !savedStub.contains(bookId) { savedStub.append(bookId) }
        } else {
            savedStub.removeAll { $0 == bookId }
        }
        return savedStub
    }

    public func getSearchIndex() async throws -> SearchIndexResponse {
        if let e = forcedError { throw e }
        if let stub = searchIndexStub { return stub }
        // Build a minimal index from the catalog stub (no chapters) as fallback.
        let books = catalogStub.map { book in
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
        return SearchIndexResponse(books: books)
    }
}
