import Observation
import CoreKit

/// View state for the progress dashboard screen.
@Observable
@MainActor
public final class DashboardModel {

    // MARK: State

    public enum LoadState {
        case loading
        case loaded(DashboardSnapshot)
        case error(AppError)
    }

    public private(set) var loadState: LoadState = .loading
    public private(set) var isRefreshing = false

    // MARK: Dependencies

    private let repository: EngagementRepository
    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    // MARK: Init

    public init(repository: EngagementRepository) {
        self.repository = repository
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Intent: load on appear

    public func load() {
        guard case .loading = loadState else { return }
        beginLoad()
    }

    // MARK: - Intent: pull-to-refresh

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await performFetch(forceRefresh: true)
    }

    // MARK: - Internal

    private func beginLoad() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performFetch(forceRefresh: false)
        }
    }

    private func performFetch(forceRefresh: Bool) async {
        do {
            let snapshot = try await repository.fetchDashboardSnapshot(forceRefresh: forceRefresh)
            loadState = .loaded(snapshot)
        } catch let appErr as AppError {
            // Keep a stale snapshot visible with an overlay error rather than blanking the screen.
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }
}
