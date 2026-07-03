import Foundation
import Observation
import CoreKit
import Models

// MARK: - LoadState

/// Async load state for a view model that fetches a list.
public enum NotebookLoadState {
    case loading
    case loaded
    case error(AppError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - NotebookModel

/// View model for the Notebook tab — aggregates all entries, drives search/filter,
/// and coordinates edit/delete with the repository.
@MainActor
@Observable
public final class NotebookModel {

    // MARK: Published state

    public private(set) var loadState: NotebookLoadState = .loading
    public private(set) var allEntries: [NotebookEntry] = []
    public private(set) var isBusy = false

    public var searchText: String = ""
    public var selectedTags: Set<String> = []
    public var selectedTypeFilter: NotebookEntryType? = nil

    // MARK: Derived

    /// Unique tags gathered from the current entry list, sorted alphabetically.
    public var availableTags: [String] {
        let tags = allEntries.flatMap { $0.effectiveTags }
        return Array(Set(tags)).sorted()
    }

    /// Entries filtered by search text, type, and selected tags.
    public var filteredEntries: [NotebookEntry] {
        var result = allEntries
        // Type filter
        if let typeFilter = selectedTypeFilter {
            result = result.filter { $0.type == typeFilter }
        }
        // Tag filter
        if !selectedTags.isEmpty {
            result = result.filter { entry in
                !selectedTags.isDisjoint(with: Set(entry.effectiveTags))
            }
        }
        // Search text
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { entry in
                let inContent = entry.content?.lowercased().contains(query) ?? false
                let inQuote = entry.quote?.lowercased().contains(query) ?? false
                let inBook = entry.bookTitle?.lowercased().contains(query) ?? false
                let inChapter = entry.chapterTitle?.lowercased().contains(query) ?? false
                let inTags = entry.effectiveTags.contains { $0.lowercased().contains(query) }
                return inContent || inQuote || inBook || inChapter || inTags
            }
        }
        // Most recent first
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Dependencies

    private let repository: NotebookRepository
    private var loadTask: Task<Void, Never>?

    // MARK: Init

    public init(repository: NotebookRepository) {
        self.repository = repository
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
        if loadState.isLoading || forceRefresh {
            loadState = .loading
        }
        do {
            let entries = try await repository.fetchEntries(forceRefresh: forceRefresh)
            allEntries = entries
            loadState = .loaded
        } catch let err as AppError {
            loadState = .error(err)
        } catch {
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
        loadTask = nil
    }

    // MARK: - Edit

    public func saveEdit(entryId: String, content: String, tags: [String]) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await repository.editEntry(
                entryId: entryId,
                content: content,
                tags: tags
            )
            if let idx = allEntries.firstIndex(where: { $0.entryId == entryId }) {
                allEntries[idx] = updated
            }
        } catch {
            // Optimistic update already applied by repo; no UI error needed for offline
        }
    }

    // MARK: - Delete

    public func deleteEntry(entryId: String) async {
        // Optimistic removal from UI first
        allEntries.removeAll { $0.entryId == entryId }
        do {
            try await repository.deleteEntry(entryId: entryId)
        } catch {
            // Offline: repo already queued; UI is already updated
        }
    }

    // MARK: - Drain

    public func drainPendingMutations() async {
        await repository.drainPendingMutations()
    }

    // MARK: - Filter helpers

    public func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    public func clearFilters() {
        searchText = ""
        selectedTags = []
        selectedTypeFilter = nil
    }

    public var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        || !selectedTags.isEmpty
        || selectedTypeFilter != nil
    }

    // MARK: - Preview seeding (internal — same module only)

    func seedForPreview(entries: [NotebookEntry], state: NotebookLoadState) {
        allEntries = entries
        loadState = state
    }
}
