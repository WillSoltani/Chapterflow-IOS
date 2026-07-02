import Models
import CoreKit

/// The data contract for the Library + Home features.
///
/// Concrete implementations: ``LiveLibraryRepository`` (production, network + cache)
/// and ``FakeLibraryRepository`` (in-memory, for tests and previews).
public protocol LibraryRepository: Sendable {
    /// Returns the full book catalog. May serve a cached copy if fresh enough.
    func getCatalog() async throws -> [BookCatalogItem]

    /// Returns per-book reading progress for all books the user has opened.
    func getProgressOverview() async throws -> ProgressOverviewResponse

    /// Returns the IDs of books the user has saved/bookmarked.
    func getSaved() async throws -> [String]

    /// Saves or un-saves a book and returns the updated saved ID list.
    func toggleSaved(bookId: String, saved: Bool) async throws -> [String]
}
