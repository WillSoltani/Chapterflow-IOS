import Foundation
import Observation
import CoreKit
import Models

// MARK: - BadgesModel

/// View model for the Badges & Achievements screen.
///
/// Fetches `GET /book/me/badges`, groups badges by track, and routes newly-earned
/// badges through the shared ``CelebrationPresenter`` so they animate in via the
/// P5.12 celebration sequence rather than competing confetti.
@Observable
@MainActor
public final class BadgesModel {

    // MARK: - Load state

    public enum LoadState {
        case loading
        case loaded([BadgeItem])
        case error(AppError)
    }

    // MARK: - Public state

    public private(set) var loadState: LoadState = .loading
    public private(set) var isRefreshing = false

    /// The track currently selected in the filter pill row. `nil` = show all.
    public var selectedTrack: AchievementTrack?

    /// The badge tapped by the user, driving the detail sheet.
    public var selectedBadge: BadgeItem?

    // MARK: - Derived

    /// All badges from the loaded state, filtered by the selected track (if any).
    public var displayedBadges: [BadgeItem] {
        guard case .loaded(let all) = loadState else { return [] }
        guard let track = selectedTrack else { return sorted(all) }
        return sorted(all.filter { AchievementTrack.from(category: $0.category) == track })
    }

    // MARK: - Dependencies

    private let repository: EngagementRepository
    private let presenter: CelebrationPresenter?

    // MARK: - Internal state

    /// Badge IDs that were already earned when this session started — used to
    /// detect genuinely new achievements without persisting across launches.
    private var seenEarnedIds: Set<String> = []
    private var initialLoadComplete = false

    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    // MARK: - Init

    public init(repository: EngagementRepository, presenter: CelebrationPresenter? = nil) {
        self.repository = repository
        self.presenter = presenter
    }

    deinit {
        loadTask?.cancel()
    }

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

    func performFetch(forceRefresh: Bool) async {
        do {
            let badges = try await repository.fetchBadges(forceRefresh: forceRefresh)
            if initialLoadComplete {
                detectAndCelebrate(badges)
            } else {
                // On first load, treat all already-earned badges as "seen" so
                // we only fire celebration for badges earned after the app launched.
                seenEarnedIds = Set(badges.filter(\.isEarned).map(\.badgeId))
                initialLoadComplete = true
            }
            loadState = .loaded(badges)
        } catch let appErr as AppError {
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    /// Compare the freshly-fetched list against the previously-seen set and
    /// fire a celebration event for each badge that crossed from locked → earned.
    private func detectAndCelebrate(_ badges: [BadgeItem]) {
        guard let presenter else { return }
        let freshEarned = badges.filter(\.isEarned)
        let newlyEarned = freshEarned.filter { !seenEarnedIds.contains($0.badgeId) }
        guard !newlyEarned.isEmpty else { return }
        for badge in newlyEarned {
            presenter.enqueue(.badgeEarned(badge: badge))
            seenEarnedIds.insert(badge.badgeId)
        }
        presenter.present()
    }

    // MARK: - Sort helpers

    /// Earned badges first (sorted by earnedAt desc), then locked by progress desc.
    private func sorted(_ badges: [BadgeItem]) -> [BadgeItem] {
        badges.sorted { lhs, rhs in
            if lhs.isEarned != rhs.isEarned { return lhs.isEarned }
            if lhs.isEarned && rhs.isEarned {
                return (lhs.earnedAt ?? "") > (rhs.earnedAt ?? "")
            }
            let lp = lhs.progressFraction ?? 0
            let rp = rhs.progressFraction ?? 0
            return lp > rp
        }
    }
}
