import Foundation
import Observation
import CoreKit
import Models

// MARK: - SavedBooksModel

/// View model for the Saved shelf — manages saved book IDs and toggle actions.
@MainActor
@Observable
public final class SavedBooksModel {

    // MARK: Published state

    public private(set) var loadState: NotebookLoadState = .loading
    public private(set) var savedBookIds: Set<String> = []
    public private(set) var catalog: [BookCatalogItem] = []

    // MARK: Derived

    /// The saved books in catalog order.
    public var savedBooks: [BookCatalogItem] {
        catalog.filter { savedBookIds.contains($0.bookId) }
    }

    // MARK: Dependencies

    private let repository: NotebookRepository
    private let fetchCatalog: @Sendable () async throws -> [BookCatalogItem]
    private var loadTask: Task<Void, Never>?

    // MARK: Init

    /// - Parameters:
    ///   - repository: The notebook/saved repository.
    ///   - fetchCatalog: Closure that returns the full book catalog (injected from LibraryRepository).
    public init(
        repository: NotebookRepository,
        fetchCatalog: @escaping @Sendable () async throws -> [BookCatalogItem]
    ) {
        self.repository = repository
        self.fetchCatalog = fetchCatalog
    }

    // MARK: - Load

    @discardableResult
    public func load() -> Task<Void, Never> {
        if let existing = loadTask { return existing }
        let task = Task { await _load() }
        loadTask = task
        return task
    }

    public func refresh() async {
        await _load(forceRefresh: true)
    }

    private func _load(forceRefresh: Bool = false) async {
        loadState = .loading
        do {
            async let ids = repository.fetchSavedBookIds(forceRefresh: forceRefresh)
            async let books = fetchCatalog()
            let (resolvedIds, resolvedBooks) = try await (ids, books)
            savedBookIds = Set(resolvedIds)
            catalog = resolvedBooks
            loadState = .loaded
        } catch let err as AppError {
            loadState = .error(err)
        } catch {
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
        loadTask = nil
    }

    // MARK: - Toggle saved

    public func toggleSaved(bookId: String) async {
        let newValue = !savedBookIds.contains(bookId)
        // Optimistic
        if newValue {
            savedBookIds.insert(bookId)
        } else {
            savedBookIds.remove(bookId)
        }
        do {
            let updatedIds = try await repository.toggleSaved(bookId: bookId, saved: newValue)
            savedBookIds = Set(updatedIds)
        } catch {
            // Already queued offline; keep optimistic state
        }
    }

    public func isSaved(_ bookId: String) -> Bool {
        savedBookIds.contains(bookId)
    }

    // MARK: - Preview seeding (internal — same module only)

    func seedForPreview(savedBookIds: Set<String>, catalog: [BookCatalogItem], state: NotebookLoadState) {
        self.savedBookIds = savedBookIds
        self.catalog = catalog
        self.loadState = state
    }
}
