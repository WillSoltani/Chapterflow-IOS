import Foundation
import Observation
import Models
import CoreKit

/// Observable model driving ``LibraryView``.
///
/// Maintains the full book catalog and saved-state, with client-side
/// search (title / author / tags) and category / saved-only filters.
@Observable
@MainActor
public final class LibraryModel {

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - State

    public private(set) var loadState: LoadState = .idle
    public private(set) var allBooks: [BookCatalogItem] = []
    public private(set) var savedBookIds: Set<String> = []

    public var searchQuery: String = ""
    public var selectedCategory: String? = nil
    public var showSavedOnly: Bool = false

    private let repository: any LibraryRepository

    // MARK: - Init

    public init(repository: any LibraryRepository) {
        self.repository = repository
    }

    // MARK: - Derived data

    /// Alphabetically sorted list of unique categories across the catalog.
    public var allCategories: [String] {
        let cats = allBooks.flatMap { $0.categories }
        return Array(Set(cats)).sorted()
    }

    /// Catalog filtered by the current search query, category, and saved-only flag.
    public var filteredBooks: [BookCatalogItem] {
        var result = allBooks

        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter { book in
                book.title.lowercased().contains(q) ||
                book.author.lowercased().contains(q) ||
                book.tags.contains { $0.lowercased().contains(q) }
            }
        }

        if let category = selectedCategory {
            result = result.filter { $0.categories.contains(category) }
        }

        if showSavedOnly {
            result = result.filter { savedBookIds.contains($0.bookId) }
        }

        return result
    }

    // MARK: - Actions

    /// Fetches catalog and saved state concurrently.
    public func fetch() async {
        loadState = .loading
        do {
            async let catalogTask = repository.getCatalog()
            async let savedTask = repository.getSaved()
            let (catalog, saved) = try await (catalogTask, savedTask)
            allBooks = catalog
            savedBookIds = Set(saved)
            loadState = .loaded
        } catch let appErr as AppError {
            loadState = .error(appErr.errorDescription ?? appErr.code)
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// Optimistically toggles the saved state for a book.
    public func toggleSaved(bookId: String) async {
        let wasSaved = savedBookIds.contains(bookId)
        if wasSaved { savedBookIds.remove(bookId) } else { savedBookIds.insert(bookId) }
        do {
            let updated = try await repository.toggleSaved(bookId: bookId, saved: !wasSaved)
            savedBookIds = Set(updated)
        } catch {
            if wasSaved { savedBookIds.insert(bookId) } else { savedBookIds.remove(bookId) }
        }
    }
}
