import Foundation
import Observation
import CoreKit
import Models

// MARK: - JourneysModel

/// View model for the journeys list screen.
///
/// Loads all available journey paths from ``JourneysRepository``.
/// The detail view handles loading individual user-journey progress.
@Observable
@MainActor
public final class JourneysModel {

    // MARK: Nested types

    public enum LoadState {
        case loading
        case loaded([JourneyCatalogItem])
        case error(AppError)
    }

    // MARK: Public state

    public private(set) var loadState: LoadState = .loading
    public private(set) var isRefreshing = false

    // MARK: Dependencies

    private let repository: JourneysRepository
    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    // MARK: Init

    public init(repository: JourneysRepository) {
        self.repository = repository
    }

    deinit { loadTask?.cancel() }

    // MARK: - Intents

    public func load() {
        guard case .loading = loadState else { return }
        beginLoad()
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await performFetch(forceRefresh: true)
    }

    // MARK: - Private

    private func beginLoad() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performFetch(forceRefresh: false)
        }
    }

    private func performFetch(forceRefresh: Bool) async {
        do {
            let journeys = try await repository.fetchJourneys(forceRefresh: forceRefresh)
            loadState = .loaded(journeys)
        } catch let appErr as AppError {
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }
}
