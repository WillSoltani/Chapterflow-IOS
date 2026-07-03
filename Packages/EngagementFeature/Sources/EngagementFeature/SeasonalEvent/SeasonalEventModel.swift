import Foundation
import Observation
import CoreKit
import Models

#if canImport(UIKit)
import UIKit
#endif

// MARK: - SeasonalEventModel

/// View model for the seasonal-events screen.
///
/// Loads the active event from ``SeasonalEventRepository``, tracks the user's
/// progress, drives the join flow, maintains a live countdown to the event end,
/// and routes the completion/badge-award moment through ``CelebrationPresenter``.
///
/// ### Countdown
/// The countdown anchors to **server time** using the offset captured by the
/// repository from the HTTP `Date` response header, not device time. This
/// prevents spurious countdowns on devices with incorrect clocks.
@Observable
@MainActor
public final class SeasonalEventModel {

    // MARK: Nested types

    public enum LoadState: Sendable {
        case loading
        case loaded(event: SeasonalEvent?, progress: EventProgress?)
        case error(AppError)
    }

    // MARK: Public state

    public private(set) var loadState: LoadState = .loading
    public private(set) var isJoining = false
    public private(set) var isRefreshing = false

    /// Remaining seconds until the event ends, based on server time.
    /// Zero when no event is loaded or the event has already ended.
    public private(set) var secondsRemaining: TimeInterval = 0

    // MARK: Dependencies

    private let repository: SeasonalEventRepository
    private let celebrationPresenter: CelebrationPresenter

    /// Cached copy of ``SeasonalEventRepository/serverTimeOffset`` — updated
    /// each time we successfully fetch the active event. Stored here to avoid
    /// actor-hopping on every countdown tick.
    private var serverTimeOffset: TimeInterval = 0

    // MARK: Tasks

    nonisolated(unsafe) private var loadTask: Task<Void, Never>?
    nonisolated(unsafe) private var countdownTask: Task<Void, Never>?

    // MARK: Init

    public init(
        repository: SeasonalEventRepository,
        celebrationPresenter: CelebrationPresenter
    ) {
        self.repository = repository
        self.celebrationPresenter = celebrationPresenter
    }

    deinit {
        loadTask?.cancel()
        countdownTask?.cancel()
    }

    // MARK: - Intents

    /// Begin loading — call from `.task {}` in the view.
    public func load() {
        guard case .loading = loadState else { return }
        beginLoad()
    }

    /// Force-refresh both event and progress.
    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await performFetch(forceRefresh: true)
    }

    /// Join the active event.
    public func join() {
        guard case .loaded(let event, _) = loadState,
              let event, !event.hasJoined, !isJoining else { return }

        isJoining = true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.joinEvent(eventId: event.eventId)
                // Re-fetch to get the server-confirmed joined state + initial progress.
                await self.performFetch(forceRefresh: true)
            } catch let appErr as AppError {
                self.loadState = .error(appErr)
            } catch {
                self.loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
            }
            self.isJoining = false
        }
    }

    /// Called by the reading loop after the server confirms a chapter completed.
    ///
    /// Posts the progress update and — if the event is now complete — fires the
    /// badge-award celebration through ``CelebrationPresenter``.
    public func onChapterCompleted() {
        guard case .loaded(let event, let progress) = loadState,
              let event, event.hasJoined,
              let progress, !progress.isCompleted else { return }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.repository.postEventProgress(eventId: event.eventId)
                // Re-fetch the event to refresh hasJoined / isActive.
                let latestEvent = try await self.repository.fetchActiveEvent(forceRefresh: false)
                self.loadState = .loaded(event: latestEvent, progress: updated)
                self.updateCountdown(for: latestEvent)
                if updated.isCompleted {
                    self.fireCelebration(event: event, progress: updated)
                }
            } catch {
                // Progress update failures are non-fatal — the UI stays in its
                // current state and the server will correct on next fetch.
            }
        }
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
            let event = try await repository.fetchActiveEvent(forceRefresh: forceRefresh)
            // Capture the server time offset now that the repository has it.
            serverTimeOffset = await repository.serverTimeOffset
            var progress: EventProgress?
            if let event, event.hasJoined {
                progress = try await repository.fetchEventProgress(eventId: event.eventId, forceRefresh: forceRefresh)
            }
            loadState = .loaded(event: event, progress: progress)
            updateCountdown(for: event)
            startCountdownLoop(for: event)
        } catch let appErr as AppError {
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    // MARK: - Countdown

    private func updateCountdown(for event: SeasonalEvent?) {
        guard let event, event.isActive else {
            secondsRemaining = 0
            return
        }
        let serverNow = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate + serverTimeOffset)
        guard let endsAt = JSONDecoder.chapterFlow.dateFromString(event.endsAt) else {
            secondsRemaining = 0
            return
        }
        secondsRemaining = max(0, endsAt.timeIntervalSince(serverNow))
    }

    private func startCountdownLoop(for event: SeasonalEvent?) {
        countdownTask?.cancel()
        guard let event, event.isActive else { return }
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await self?.tickCountdown(event: event)
            }
        }
    }

    private func tickCountdown(event: SeasonalEvent) {
        updateCountdown(for: event)
    }

    // MARK: - Celebration

    private func fireCelebration(event: SeasonalEvent, progress: EventProgress) {
        fireHaptic()
        celebrationPresenter.enqueue(.eventComplete(eventTitle: event.title, badge: event.badge))
        if let badge = event.badge {
            celebrationPresenter.enqueue(.badgeEarned(badge: badge))
        }
        if event.bonusIp > 0 {
            celebrationPresenter.enqueue(.flowPointsGained(points: event.bonusIp))
        }
        celebrationPresenter.present()
    }

    private func fireHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }
}

// MARK: - Countdown formatting helpers

extension SeasonalEventModel {

    /// Formats `secondsRemaining` as "Xd Xh Xm" or "Xh Xm Xs".
    public var countdownText: String {
        Self.formatCountdown(seconds: secondsRemaining)
    }

    /// Formats a raw seconds value into a human-readable countdown string.
    /// `internal` so unit tests can call it directly without needing to mutate
    /// the `public private(set)` `secondsRemaining` property.
    static func formatCountdown(seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60

        if days > 0 {
            return String(format: "%dd %dh %dm", days, hours, minutes)
        } else if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else {
            return String(format: "%dm %ds", minutes, secs)
        }
    }
}

// MARK: - JSONDecoder helper

private extension JSONDecoder {
    func dateFromString(_ string: String) -> Date? {
        try? decode(DateWrapper.self, from: Data("\"\(string)\"".utf8)).date
    }

    private struct DateWrapper: Decodable {
        let date: Date
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.date = try container.decode(Date.self)
        }
    }
}
