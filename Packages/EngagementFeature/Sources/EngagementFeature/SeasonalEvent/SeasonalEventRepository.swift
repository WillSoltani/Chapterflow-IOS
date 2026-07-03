import Foundation
import CoreKit
import Models
import Networking
import OSLog

private let log = Logger(subsystem: "com.chapterflow.engagement", category: "seasonal-events")

// MARK: - SeasonalEventRepository

/// The data layer for seasonal events.
///
/// Exposes the three event endpoints:
/// - `GET /book/events/active`
/// - `POST /book/me/events/{id}/join`
/// - `GET|POST /book/me/events/{id}/progress`
///
/// The repository stores the **server time offset** captured from the HTTP
/// `Date` response header when the active event is fetched. Callers use
/// ``serverTimeOffset`` to anchor countdowns to server clock instead of the
/// (potentially skewed) device clock.
public actor SeasonalEventRepository {

    // MARK: Dependencies

    private let apiClient: any APIClientProtocol

    // MARK: In-memory cache

    private struct MemEntry<T: Sendable> {
        let value: T
        let storedAt: Date
        func isStale(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(storedAt) >= ttl
        }
    }

    private var memEvent: MemEntry<SeasonalEvent?>?
    private var memProgress: MemEntry<EventProgress>?

    private let eventTTL: TimeInterval = 5 * 60
    private let progressTTL: TimeInterval = 2 * 60

    // MARK: Server clock offset

    /// Seconds to add to the current device time to approximate server time.
    ///
    /// Populated from the HTTP `Date` header when ``fetchActiveEvent()`` succeeds.
    /// Zero when the header is absent or not yet fetched — falls back to device time.
    public private(set) var serverTimeOffset: TimeInterval = 0

    // MARK: Init

    public init(apiClient: some APIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Fetch active event

    /// Returns the currently active event, or `nil` if none is running.
    ///
    /// Caches the result for `eventTTL`. Also captures the server time offset
    /// from the HTTP `Date` header so the model can display server-accurate countdowns.
    public func fetchActiveEvent(forceRefresh: Bool = false) async throws -> SeasonalEvent? {
        if !forceRefresh, let entry = memEvent, !entry.isStale(ttl: eventTTL) {
            return entry.value
        }
        let (resp, serverDate): (ActiveEventResponse, Date?) = try await apiClient.sendWithServerDate(
            Endpoints.getActiveEvent()
        )
        let event = resp.event
        memEvent = MemEntry(value: event, storedAt: Date())
        // Compute offset from the server's claimed current time vs device time.
        if let serverDate {
            serverTimeOffset = serverDate.timeIntervalSinceReferenceDate - Date().timeIntervalSinceReferenceDate
        }
        return event
    }

    // MARK: - Join event

    /// Joins the event with the given id.
    /// Updates the cached event to reflect `hasJoined = true` optimistically
    /// (the server is the authority on completion / progress).
    public func joinEvent(eventId: String) async throws {
        let endpoint = try Endpoints.joinEvent(eventId: eventId)
        let resp: JoinEventResponse = try await apiClient.send(endpoint)
        // Update cached event from the response if available.
        if let updatedEvent = resp.event {
            memEvent = MemEntry(value: updatedEvent, storedAt: Date())
        }
        // Cache initial progress if the server returned it.
        if let updatedProgress = resp.progress {
            memProgress = MemEntry(value: updatedProgress, storedAt: Date())
        }
    }

    // MARK: - Event progress

    /// Fetches the user's progress for the given event.
    public func fetchEventProgress(eventId: String, forceRefresh: Bool = false) async throws -> EventProgress {
        if !forceRefresh, let entry = memProgress, !entry.isStale(ttl: progressTTL) {
            return entry.value
        }
        let resp: EventProgressResponse = try await apiClient.send(Endpoints.getEventProgress(eventId: eventId))
        let progress = resp.progress
        memProgress = MemEntry(value: progress, storedAt: Date())
        return progress
    }

    /// Posts a chapter-complete event to the server and returns updated progress.
    ///
    /// Call this after the server confirms a chapter was completed (not client-side).
    public func postEventProgress(eventId: String) async throws -> EventProgress {
        let endpoint = try Endpoints.postEventProgress(eventId: eventId)
        let resp: EventProgressResponse = try await apiClient.send(endpoint)
        let progress = resp.progress
        memProgress = MemEntry(value: progress, storedAt: Date())
        return progress
    }

    // MARK: - Cache invalidation

    public func invalidateAll() {
        memEvent = nil
        memProgress = nil
    }
}
