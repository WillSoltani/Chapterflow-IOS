import Foundation
import Observation
import Models
import CoreKit

/// Observable model driving ``DiscoverView``.
///
/// Derives curated shelves (New, Popular, For You, by category) from the catalog
/// in memory so shelf switching is instant without extra network calls.
/// The "For You" shelf is seeded by the user's interest categories injected from
/// outside (onboarding selections, or the categories of their in-progress books).
@Observable
@MainActor
public final class DiscoverModel {

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - State

    public private(set) var loadState: LoadState = .idle
    public private(set) var books: [BookCatalogItem] = []
    public private(set) var savedBookIds: Set<String> = []

    /// Categories the user expressed interest in (from onboarding or in-progress books).
    public var userInterests: [String]

    private let repository: any LibraryRepository

    // MARK: - Init

    public init(repository: any LibraryRepository, userInterests: [String] = []) {
        self.repository = repository
        self.userInterests = userInterests
    }

    // MARK: - Curated shelves

    /// Books sorted by `updatedAt` descending — the "New & Updated" shelf.
    /// `updatedAt` is optional on the wire (the deployed catalog omits it);
    /// ties (including the all-nil case) break on `bookId` so the shelf order
    /// is STABLE across fetches (Swift's sort is not stability-guaranteed).
    public var newBooks: [BookCatalogItem] {
        books
            .sorted {
                let lhs = $0.updatedAt ?? ""
                let rhs = $1.updatedAt ?? ""
                if lhs != rhs { return lhs > rhs }
                return $0.bookId < $1.bookId
            }
            .prefix(12)
            .map { $0 }
    }

    /// "Popular" — catalog order (server implicitly orders by engagement).
    /// Capped at 12 for the shelf.
    public var popularBooks: [BookCatalogItem] {
        Array(books.prefix(12))
    }

    /// "For You" — books whose categories overlap with the user's interests.
    /// Falls back to `popularBooks` when interests are empty.
    public var forYouBooks: [BookCatalogItem] {
        guard !userInterests.isEmpty else { return popularBooks }
        let interestSet = Set(userInterests.map { $0.lowercased() })
        let matched = books.filter { book in
            book.categories.contains { interestSet.contains($0.lowercased()) }
        }
        return matched.isEmpty ? popularBooks : Array(matched.prefix(12))
    }

    /// All books grouped by their primary category, sorted alphabetically.
    public var booksByCategory: [(category: String, books: [BookCatalogItem])] {
        var grouped: [String: [BookCatalogItem]] = [:]
        for book in books {
            let cat = book.categories.first ?? "Other"
            grouped[cat, default: []].append(book)
        }
        return grouped
            .map { (category: $0.key, books: $0.value) }
            .sorted { $0.category < $1.category }
    }

    /// Sorted, unique category names for the browse grid.
    public var allCategories: [String] {
        let cats = books.flatMap { $0.categories }
        return Array(Set(cats)).sorted()
    }

    // MARK: - Actions

    /// Fetches the full catalog and saved state concurrently.
    public func fetch() async {
        loadState = .loading
        do {
            async let catalogTask = repository.getCatalog()
            async let savedTask = repository.getSaved()
            let (catalog, saved) = try await (catalogTask, savedTask)
            books = catalog
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
