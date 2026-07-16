import CoreKit
import LibraryFeature
import Models

/// Public-only guest facade. It never constructs or reaches an account graph.
struct GuestPublicLibraryRepository: LibraryRepository {
    let base: any LibraryRepository

    func getCatalog() async throws -> [BookCatalogItem] {
        try await base.getCatalog()
    }

    func getProgressOverview() async throws -> ProgressOverviewResponse {
        ProgressOverviewResponse(progress: [])
    }

    func getSaved() async throws -> [String] { [] }

    func toggleSaved(bookId: String, saved: Bool) async throws -> [String] {
        _ = (bookId, saved)
        throw AppError.unauthenticated
    }

    func getSearchIndex() async throws -> SearchIndexResponse {
        try await base.getSearchIndex()
    }
}

/// Public book metadata remains available to guests; every private operation
/// fails closed at the repository boundary.
struct GuestPublicBookDetailRepository: BookDetailRepository {
    let base: any BookDetailRepository

    func getBook(id: String) async throws -> BookManifest {
        try await base.getBook(id: id)
    }

    func getBookState(id: String) async throws -> BookStateGetResponse {
        _ = id
        throw AppError.unauthenticated
    }

    func startBook(id: String) async throws -> BookStateResponse {
        _ = id
        throw AppError.unauthenticated
    }

    func getEntitlements() async throws -> EntitlementResponse {
        throw AppError.unauthenticated
    }
}
