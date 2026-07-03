import Foundation
import Observation
import CoreKit
import Models

// MARK: - JourneyDetailModel

/// View model for the journey detail screen.
///
/// Loads user-journey progress and provides start/continue actions.
/// Fires a ``CelebrationEvent/journeyComplete(title:)`` the first time the
/// server reports the journey as completed.
@Observable
@MainActor
public final class JourneyDetailModel {

    // MARK: Nested types

    public enum LoadState {
        case loading
        case loaded(UserJourney)
        case error(AppError)
        /// User has not yet enrolled in this journey.
        case notStarted
    }

    // MARK: Public state

    public private(set) var loadState: LoadState = .loading
    public private(set) var isRefreshing = false
    public private(set) var isStarting = false

    /// The catalog journey data (passed in at init, always available).
    public let journey: JourneyCatalogItem

    /// Shared celebration presenter — mount `.celebrationOverlay(model.celebrationPresenter)` in the view.
    public let celebrationPresenter: CelebrationPresenter

    // MARK: Dependencies

    private let repository: JourneysRepository
    private let userDefaults: UserDefaults
    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    private static func celebrationKey(journeyId: String) -> String {
        "com.chapterflow.journey.completion.\(journeyId)"
    }

    // MARK: Init

    public init(
        journey: JourneyCatalogItem,
        repository: JourneysRepository,
        celebrationPresenter: CelebrationPresenter,
        userDefaults: UserDefaults = .standard
    ) {
        self.journey = journey
        self.repository = repository
        self.celebrationPresenter = celebrationPresenter
        self.userDefaults = userDefaults
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

    /// Enroll in the journey (server-authoritative — never grant locally).
    public func start() async {
        isStarting = true
        defer { isStarting = false }
        do {
            let userJourney = try await repository.startJourney(id: journey.journeyId)
            loadState = .loaded(userJourney)
            checkAndFireCompletion(userJourney)
        } catch let appErr as AppError {
            loadState = .error(appErr)
        } catch {
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    // MARK: - Derived state

    /// 0-based index of the book the user is currently working on, or nil if not started.
    public var currentBookIndex: Int? {
        guard case .loaded(let uj) = loadState else { return nil }
        return uj.currentBookIndex
    }

    /// The active book entry (the one to open when tapping Start / Continue).
    public var activeBook: JourneyBookEntry? {
        guard let idx = currentBookIndex else { return nil }
        let sorted = journey.books.sorted { $0.order < $1.order }
        guard idx < sorted.count else { return sorted.last }
        return sorted[idx]
    }

    /// Whether the user has enrolled in this journey.
    public var isEnrolled: Bool {
        if case .loaded = loadState { return true }
        return false
    }

    /// Whether the journey is fully complete.
    public var isCompleted: Bool {
        guard case .loaded(let uj) = loadState else { return false }
        return uj.isCompleted
    }

    /// Progress fraction 0–1 based on completed books.
    public var progressFraction: Double {
        guard case .loaded(let uj) = loadState else { return 0 }
        let total = journey.books.count
        guard total > 0 else { return 0 }
        return min(1.0, Double(uj.completedBookIds.count) / Double(total))
    }

    /// Book IDs the user has completed, or empty if not started.
    public var completedBookIds: [String] {
        guard case .loaded(let uj) = loadState else { return [] }
        return uj.completedBookIds
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
            let userJourney = try await repository.fetchUserJourney(
                id: journey.journeyId,
                forceRefresh: forceRefresh
            )
            loadState = .loaded(userJourney)
            checkAndFireCompletion(userJourney)
        } catch AppError.notFound {
            // 404 means the user hasn't enrolled yet.
            loadState = .notStarted
        } catch let appErr as AppError {
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    private func checkAndFireCompletion(_ userJourney: UserJourney) {
        guard userJourney.isCompleted else { return }
        let key = Self.celebrationKey(journeyId: journey.journeyId)
        guard !userDefaults.bool(forKey: key) else { return }
        userDefaults.set(true, forKey: key)
        celebrationPresenter.enqueue(.journeyComplete(title: journey.title))
        celebrationPresenter.present()
    }
}
