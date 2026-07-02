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

    public init(
        catalog: [BookCatalogItem] = [],
        progress: ProgressOverviewResponse = ProgressOverviewResponse(progress: []),
        savedBookIds: [String] = [],
        error: AppError? = nil
    ) {
        self.catalogStub = catalog
        self.progressStub = progress
        self.savedStub = savedBookIds
        self.forcedError = error
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
}
