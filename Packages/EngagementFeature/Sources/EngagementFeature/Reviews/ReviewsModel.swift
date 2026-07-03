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

    // MARK: Init

    public init(repository: ReviewsRepository) {
        self.repository = repository
    }

    // MARK: - Load

    /// Loads the due-card count for the hub view.
    public func load() {
        guard case .idle = loadState else { return }
        Task { await fetch() }
    }

    public func refresh() async {
        await fetch(forceRefresh: true)
    }

    private func fetch(forceRefresh: Bool = false) async {
        loadState = .loading
        do {
            let resp = try await repository.fetchDueCards(forceRefresh: forceRefresh)
            let nextDue = resp.cards
                .compactMap { $0.dueDate }
                .filter { $0 > Date() }
                .sorted()
                .first
            loadState = .loaded(dueCount: resp.dueCount, nextDue: nextDue)
            pendingGradeCount = await repository.pendingGradeCount()
        } catch {
            loadState = .error(AppError(from: error))
        }
    }

    // MARK: - Session lifecycle

    /// Starts a review session with the currently cached due cards.
    public func startSession() {
        Task {
            do {
                let resp = try await repository.fetchDueCards()
                let due  = resp.cards.filter { $0.isDue() }
                guard !due.isEmpty else {
                    sessionState = .done(reviewed: 0)
                    return
                }
                sessionCards = due
                sessionIndex = 0
                sessionState = .front
            } catch {
                loadState = .error(AppError(from: error))
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
              let card = sessionCards[safe: sessionIndex] else { return }

        let capturedCard  = card
        let capturedGrade = gradeValue

        // Advance the UI immediately — do NOT await the network call first.
        advanceSession()

        // Fire-and-forget: the repository handles offline outbox on failure.
        Task {
            do {
                _ = try await repository.gradeCard(capturedCard, grade: capturedGrade)
            } catch {
                // Offline grades are queued in the SwiftData outbox inside the
                // repository; non-retryable errors are logged there.
            }
        }
    }

    private func advanceSession() {
        sessionIndex += 1
        if sessionIndex >= sessionCards.count {
            sessionState = .done(reviewed: sessionCards.count)
            Task { await fetch(forceRefresh: true) }
        } else {
            sessionState = .front
        }
    }

    /// Ends the session and returns to the hub.
    public func endSession() {
        sessionState = .inactive
        sessionCards = []
        sessionIndex = 0
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
