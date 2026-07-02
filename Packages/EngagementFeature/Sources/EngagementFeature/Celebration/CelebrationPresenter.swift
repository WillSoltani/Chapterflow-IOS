import Foundation
import Observation

// MARK: - CelebrationPresenter

/// The single source of truth for the reward/celebration layer.
///
/// Features enqueue events via ``enqueue(_:)``. The presenter serialises them
/// into one non-overlapping sequence shown through ``CelebrationView``.
///
/// ### Usage
/// ```swift
/// // At the call-site (e.g. after a quiz pass + server refresh):
/// presenter.enqueue(.loopComplete(chapterTitle: "Chapter 3"))
/// presenter.enqueue(.flowPointsGained(points: 50))
/// presenter.enqueue(.streakIncrement(newStreak: 5))
/// presenter.present()
/// ```
@MainActor
@Observable
public final class CelebrationPresenter {

    // MARK: Public state

    /// The event currently being shown, or `nil` when the sequence is idle.
    public private(set) var currentEvent: CelebrationEvent?

    /// `true` while a celebration sequence is actively running.
    public var isPresenting: Bool { currentEvent != nil }

    // MARK: Private state

    private var queue: [CelebrationEvent] = []
    private var autoAdvanceTask: Task<Void, Never>?

    // MARK: Init

    public init() {}

    // MARK: - Public API

    /// Add an event to the pending queue.
    ///
    /// Events are played in the order they are enqueued. Calling this while a
    /// sequence is already running simply appends to the tail — the new event
    /// will appear after the current one finishes.
    public func enqueue(_ event: CelebrationEvent) {
        queue.append(event)
    }

    /// Enqueue multiple events at once.
    public func enqueue(_ events: [CelebrationEvent]) {
        queue.append(contentsOf: events)
    }

    /// Start presenting the queued events. If already presenting, this is a no-op
    /// (the queue will drain naturally). Call this after enqueuing all events for
    /// a single action so the sequence begins atomically.
    public func present() {
        guard currentEvent == nil else { return }
        advance()
    }

    /// Skip the current event and move to the next one immediately.
    public func advance() {
        cancelAutoAdvance()
        if queue.isEmpty {
            currentEvent = nil
        } else {
            currentEvent = queue.removeFirst()
            scheduleAutoAdvance(after: currentEvent?.autoAdvanceDuration ?? 2.5)
        }
    }

    /// Dismiss the whole sequence immediately, discarding any remaining events.
    public func dismissAll() {
        cancelAutoAdvance()
        queue.removeAll()
        currentEvent = nil
    }

    // MARK: - Private helpers

    private func scheduleAutoAdvance(after seconds: TimeInterval) {
        autoAdvanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.advance()
        }
    }

    private func cancelAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }
}
