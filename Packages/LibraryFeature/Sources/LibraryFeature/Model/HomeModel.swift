import Foundation
import Observation
import Models
import CoreKit

/// Observable model driving ``HomeView``.
///
/// Loads catalog, per-book progress, and saved book IDs concurrently.
/// All mutations are on the main actor; the underlying repository is actor-isolated.
@Observable
@MainActor
public final class HomeModel {

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - State

    public private(set) var loadState: LoadState = .idle
    public private(set) var books: [BookCatalogItem] = []
    public private(set) var progressItems: [ProgressOverviewItem] = []
    public private(set) var savedBookIds: Set<String> = []

    /// O(1) lookup map rebuilt once per fetch — avoids O(n×m) scan in `continueReadingBooks`.
    @ObservationIgnored private var bookMap: [String: BookCatalogItem] = [:]

    private let repository: any LibraryRepository

    // MARK: - Init

    public init(repository: any LibraryRepository) {
        self.repository = repository
    }

    // MARK: - Derived data

    /// Books the user is currently reading, sorted by most-recently-opened first.
    ///
    /// Uses the pre-built `bookMap` dictionary (O(1) per lookup) built in `fetch()`.
    public var continueReadingBooks: [(book: BookCatalogItem, progress: ProgressOverviewItem)] {
        progressItems
            .compactMap { item -> (BookCatalogItem, ProgressOverviewItem)? in
                guard let book = bookMap[item.bookId] else { return nil }
                return (book, item)
            }
            .sorted { ($0.1.lastReadAt ?? "") > ($1.1.lastReadAt ?? "") }
    }

    /// The user's saved books as full catalog items.
    public var savedBooks: [BookCatalogItem] {
        books.filter { savedBookIds.contains($0.bookId) }
    }

    /// Catalog grouped by primary category for the Discover section.
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

    // MARK: - Actions

    /// Fetches catalog, progress, and saved state concurrently.
    public func fetch() async {
        loadState = .loading
        do {
            async let catalogTask = repository.getCatalog()
            async let progressTask = repository.getProgressOverview()
            async let savedTask = repository.getSaved()
            let (catalog, progress, saved) = try await (catalogTask, progressTask, savedTask)
            books = catalog
            bookMap = Dictionary(uniqueKeysWithValues: catalog.map { ($0.bookId, $0) })
            progressItems = progress.progress
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
        // Optimistic update
        if wasSaved { savedBookIds.remove(bookId) } else { savedBookIds.insert(bookId) }
        do {
            let updated = try await repository.toggleSaved(bookId: bookId, saved: !wasSaved)
            savedBookIds = Set(updated)
        } catch {
            // Revert on failure
            if wasSaved { savedBookIds.insert(bookId) } else { savedBookIds.remove(bookId) }
        }
    }
}
