import SwiftUI
import Observation
import Models
import CoreKit

// MARK: - ReviewsModel

/// Observable view model for the Reviews tab and session flow.
///
/// Owns the full review-session state machine:
///
/// ```
///  idle → loading → loaded (due cards) → session → done
///                 └→ empty (no cards due)
/// ```
@Observable
@MainActor
public final class ReviewsModel {

    // MARK: Dependency

    private let repository: ReviewsRepository
    private let analytics: any AnalyticsClient
    private let workPermit: SessionWorkPermit
    @ObservationIgnored private var gradeTask: Task<Void, Never>?

    // MARK: Load state

    public enum LoadState: Sendable {
        case idle
        case loading
        case loaded(dueCount: Int, nextDue: Date?)
        case error(AppError)
    }

    public var loadState: LoadState = .idle

    // MARK: Session state

    public enum SessionState: Sendable, Equatable {
        /// Not in a session.
        case inactive
        /// Showing the front of the current card.
        case front
        /// Card flipped — back visible, grade buttons active.
        case back
        /// Session complete.
        case done(reviewed: Int)
    }

    public var sessionState: SessionState = .inactive

    // MARK: Session data

    private var sessionCards: [FsrsCard] = []
    private var sessionIndex: Int = 0

    /// The card currently under review (nil between cards or when the session is inactive).
    public var currentCard: FsrsCard? {
        guard case .front = sessionState else {
            if case .back = sessionState { return sessionCards[safe: sessionIndex] }
            return nil
        }
        return sessionCards[safe: sessionIndex]
    }

    /// Progress through the session: (completed, total).
    public var sessionProgress: (Int, Int) {
        (sessionIndex, sessionCards.count)
    }

    public var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    // MARK: Offline pending badge

    public private(set) var pendingGradeCount: Int = 0
    public private(set) var isGrading = false
    public private(set) var gradeError: AppError?

    // MARK: Init

    public init(
        repository: ReviewsRepository,
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        analytics: any AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.repository = repository
        self.workPermit = workPermit
        self.analytics = analytics
    }

    // MARK: - Load

    /// Loads the due-card count for the hub view.
    public func load() {
        guard case .idle = loadState else { return }
        guard let ticket = try? workPermit.begin() else { return }
        Task { await fetch(ticket: ticket) }
    }

    public func refresh() async {
        guard let ticket = try? workPermit.begin() else { return }
        await fetch(forceRefresh: true, ticket: ticket)
    }

    private func fetch(forceRefresh: Bool = false, ticket: UInt64) async {
        try? workPermit.commit(ticket) {
            loadState = .loading
        }
        do {
            let resp = try await repository.fetchDueCards(forceRefresh: forceRefresh)
            let nextDue = resp.cards
                .compactMap { $0.dueDate }
                .filter { $0 > Date() }
                .sorted()
                .first
            let pendingCount = await repository.pendingGradeCount()
            try workPermit.commit(ticket) {
                loadState = .loaded(dueCount: resp.dueCount, nextDue: nextDue)
                pendingGradeCount = pendingCount
            }
        } catch is CancellationError {
            return
        } catch {
            try? workPermit.commit(ticket) {
                loadState = .error(AppError(from: error))
            }
        }
    }

    // MARK: - Session lifecycle

    /// Starts a review session with the currently cached due cards.
    public func startSession() {
        guard let ticket = try? workPermit.begin() else { return }
        Task {
            do {
                let resp = try await repository.fetchDueCards()
                let due  = resp.cards.filter { $0.isDue() }
                guard !due.isEmpty else {
                    try workPermit.commit(ticket) {
                        sessionState = .done(reviewed: 0)
                    }
                    return
                }
                try workPermit.commit(ticket) {
                    sessionCards = due
                    sessionIndex = 0
                    sessionState = .front
                }
            } catch is CancellationError {
                return
            } catch {
                try? workPermit.commit(ticket) {
                    loadState = .error(AppError(from: error))
                }
            }
        }
    }

    /// Flips the current card to reveal the back.
    public func revealBack() {
        guard case .front = sessionState else { return }
        sessionState = .back
    }

    /// Grades the current card and advances to the next.
    ///
    /// Advances the UI immediately (optimistic), then submits the grade in a
    /// background task so the session never blocks on the network.
    public func grade(_ gradeValue: FSRSGrade) {
        guard case .back = sessionState,
              let card = sessionCards[safe: sessionIndex],
              !isGrading,
              let ticket = try? workPermit.begin() else { return }

        let capturedCard  = card
        let capturedGrade = gradeValue
        isGrading = true
        gradeError = nil
        gradeTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await repository.gradeCard(capturedCard, grade: capturedGrade)
                try workPermit.commit(ticket) {
                    isGrading = false
                    advanceSession(ticket: ticket)
                }
            } catch is CancellationError {
                return
            } catch {
                try? workPermit.commit(ticket) {
                    isGrading = false
                    gradeError = AppError(from: error)
                }
            }
        }
    }

    private func advanceSession(ticket: UInt64) {
        sessionIndex += 1
        if sessionIndex >= sessionCards.count {
            analytics.track(.reviewCompleted(reviewed: sessionCards.count))
            sessionState = .done(reviewed: sessionCards.count)
            Task { await fetch(forceRefresh: true, ticket: ticket) }
        } else {
            sessionState = .front
        }
    }

    /// Ends the session and returns to the hub.
    public func endSession() {
        gradeTask?.cancel()
        gradeTask = nil
        guard let ticket = try? workPermit.begin() else { return }
        try? workPermit.commit(ticket) {
            sessionState = .inactive
            sessionCards = []
            sessionIndex = 0
            isGrading = false
            gradeError = nil
        }
    }
}

// MARK: - AppError bridge

private extension AppError {
    init(from error: Error) {
        if let appError = error as? AppError {
            self = appError
        } else {
            self = .server(code: "unknown", message: error.localizedDescription, requestId: nil)
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
