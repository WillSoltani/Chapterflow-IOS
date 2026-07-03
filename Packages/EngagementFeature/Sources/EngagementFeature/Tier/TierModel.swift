import Foundation
import Observation
import CoreKit
import Models

#if canImport(UIKit)
import UIKit
#endif

// MARK: - TierModel

/// View model for the tier screen.
///
/// Loads tier data from ``EngagementRepository``, detects promotions, and fires a
/// one-per-tier ``CelebrationEvent/tierUp(newTier:previousTier:)`` through the shared
/// ``CelebrationPresenter`` — never competing confetti.
@Observable
@MainActor
public final class TierModel {

    // MARK: - Nested types

    public enum LoadState {
        case loading
        case loaded(TierState)
        case error(AppError)
    }

    // MARK: - Public state

    public private(set) var loadState: LoadState = .loading
    public private(set) var isRefreshing = false
    /// Controls the tier explainer sheet.
    public var showExplainer = false

    // MARK: - Dependencies

    private let repository: EngagementRepository
    private let celebrationPresenter: CelebrationPresenter
    private let userDefaults: UserDefaults

    // MARK: - Internal

    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    // MARK: - Constants

    /// UserDefaults key tracking the highest tier we've already celebrated.
    static let celebratedTierKey = "com.chapterflow.tier.celebratedTier"

    // MARK: - Init

    public init(
        repository: EngagementRepository,
        celebrationPresenter: CelebrationPresenter,
        userDefaults: UserDefaults = .standard
    ) {
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

    // MARK: - Derived state

    /// The current tier, or `.reader` when no data is loaded yet.
    public var currentTier: TierKey {
        guard case .loaded(let state) = loadState else { return .reader }
        return state.currentTier
    }

    /// Overall 0–1 progress fraction to the next tier.
    public var overallProgress: Double {
        guard case .loaded(let state) = loadState else { return 0 }
        return state.overallProgress
    }

    /// Progress fraction (0–1) for loops-completed metric.
    public var loopsProgress: Double {
        guard case .loaded(let state) = loadState,
              let m = state.metrics,
              let target = m.loopsTarget, target > 0 else { return 0 }
        return min(1.0, Double(m.loopsCompleted) / Double(target))
    }

    /// Progress fraction (0–1) for the average quiz score metric.
    public var quizScoreProgress: Double {
        guard case .loaded(let state) = loadState,
              let m = state.metrics,
              let target = m.quizScoreTarget, target > 0 else { return 0 }
        return min(1.0, m.averageQuizScore / target)
    }

    /// Progress fraction (0–1) for categories-explored metric.
    public var categoriesProgress: Double {
        guard case .loaded(let state) = loadState,
              let m = state.metrics,
              let target = m.categoriesTarget, target > 0 else { return 0 }
        return min(1.0, Double(m.categoriesExplored) / Double(target))
    }

    // MARK: - Private load

    private func beginLoad() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performFetch(forceRefresh: false)
        }
    }

    private func performFetch(forceRefresh: Bool) async {
        do {
            let tierState = try await repository.fetchTier(forceRefresh: forceRefresh)
            checkAndFireCelebration(tierState)
            loadState = .loaded(tierState)
        } catch let appErr as AppError {
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    // MARK: - Celebration guard (once per tier level)

    /// Fires `.tierUp` at most once per tier level.
    ///
    /// The server's `recentlyPromoted` flag is the primary signal. We also guard
    /// using `UserDefaults` so that app restarts don't replay the same celebration.
    private func checkAndFireCelebration(_ state: TierState) {
        guard state.recentlyPromoted == true else { return }

        let newTierRaw = state.currentTier.rawValue
        let alreadyCelebrated = userDefaults.string(forKey: Self.celebratedTierKey)
        guard alreadyCelebrated != newTierRaw else { return }

        userDefaults.set(newTierRaw, forKey: Self.celebratedTierKey)

        fireHaptic()

        let previousRaw = state.previousTier?.rawValue
        celebrationPresenter.enqueue(.tierUp(newTier: newTierRaw, previousTier: previousRaw))
        celebrationPresenter.present()
    }

    private func fireHaptic() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}
