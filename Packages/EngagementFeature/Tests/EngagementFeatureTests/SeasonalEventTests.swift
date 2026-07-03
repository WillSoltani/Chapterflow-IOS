import Testing
import Foundation
@testable import EngagementFeature
import Models
import CoreKit
import Networking

// MARK: - SeasonalEventRepository tests

@Suite("SeasonalEventRepository")
struct SeasonalEventRepositoryTests {

    // MARK: - Fixtures

    private static func makeEvent(hasJoined: Bool = false) -> SeasonalEvent {
        SeasonalEvent(
            eventId: "evt-1",
            title: "Summer Challenge",
            description: "Read 20 chapters.",
            startsAt: "2026-07-01T00:00:00Z",
            endsAt: "2026-07-31T23:59:59Z",
            targetChapters: 20,
            dailyTarget: 1,
            badge: nil,
            bonusIp: 300,
            isActive: true,
            hasJoined: hasJoined
        )
    }

    private static func makeProgress(completed: Bool = false) -> EventProgress {
        EventProgress(
            eventId: "evt-1",
            chaptersCompleted: completed ? 20 : 5,
            dailyChaptersCompleted: 1,
            isCompleted: completed,
            joinedAt: "2026-07-03T08:00:00Z",
            completedAt: completed ? "2026-07-28T15:00:00Z" : nil
        )
    }

    // MARK: - fetchActiveEvent

    @Test("fetchActiveEvent returns event from server")
    func fetchActiveEventSuccess() async throws {
        let event = Self.makeEvent()
        let client = EventTestClient(event: event, progress: nil)
        let sut = SeasonalEventRepository(apiClient: client)
        let result = try await sut.fetchActiveEvent()
        #expect(result?.eventId == "evt-1")
        #expect(result?.title == "Summer Challenge")
    }

    @Test("fetchActiveEvent returns nil when no event is active")
    func fetchActiveEventNone() async throws {
        let client = EventTestClient(event: nil, progress: nil)
        let sut = SeasonalEventRepository(apiClient: client)
        let result = try await sut.fetchActiveEvent()
        #expect(result == nil)
    }

    @Test("fetchActiveEvent uses memory cache on second call")
    func fetchActiveEventCacheHit() async throws {
        let event = Self.makeEvent()
        let client = EventTestClient(event: event, progress: nil)
        let sut = SeasonalEventRepository(apiClient: client)
        _ = try await sut.fetchActiveEvent()
        _ = try await sut.fetchActiveEvent()
        // Should only have called the server once.
        #expect(client.activeEventCallCount == 1)
    }

    @Test("fetchActiveEvent bypasses cache when forceRefresh is true")
    func fetchActiveEventForceRefresh() async throws {
        let event = Self.makeEvent()
        let client = EventTestClient(event: event, progress: nil)
        let sut = SeasonalEventRepository(apiClient: client)
        _ = try await sut.fetchActiveEvent()
        _ = try await sut.fetchActiveEvent(forceRefresh: true)
        #expect(client.activeEventCallCount == 2)
    }

    // MARK: - joinEvent

    @Test("joinEvent updates cached event to hasJoined=true")
    func joinEventUpdatesCache() async throws {
        let event = Self.makeEvent(hasJoined: false)
        let client = EventTestClient(event: event, progress: nil)
        let sut = SeasonalEventRepository(apiClient: client)
        _ = try await sut.fetchActiveEvent()
        try await sut.joinEvent(eventId: "evt-1")
        // After join, cached event should reflect joined state.
        let cached = try await sut.fetchActiveEvent(forceRefresh: false)
        #expect(cached?.hasJoined == true)
    }

    // MARK: - fetchEventProgress

    @Test("fetchEventProgress returns progress from server")
    func fetchEventProgressSuccess() async throws {
        let event = Self.makeEvent(hasJoined: true)
        let progress = Self.makeProgress()
        let client = EventTestClient(event: event, progress: progress)
        let sut = SeasonalEventRepository(apiClient: client)
        let result = try await sut.fetchEventProgress(eventId: "evt-1")
        #expect(result.chaptersCompleted == 5)
        #expect(result.isCompleted == false)
    }

    @Test("fetchEventProgress uses memory cache")
    func fetchEventProgressCacheHit() async throws {
        let progress = Self.makeProgress()
        let client = EventTestClient(event: nil, progress: progress)
        let sut = SeasonalEventRepository(apiClient: client)
        _ = try await sut.fetchEventProgress(eventId: "evt-1")
        _ = try await sut.fetchEventProgress(eventId: "evt-1")
        #expect(client.progressCallCount == 1)
    }

    // MARK: - postEventProgress

    @Test("postEventProgress returns updated progress and invalidates cache")
    func postEventProgressUpdatesCache() async throws {
        let event = Self.makeEvent(hasJoined: true)
        let progress = Self.makeProgress(completed: true)
        let client = EventTestClient(event: event, progress: progress)
        let sut = SeasonalEventRepository(apiClient: client)
        let result = try await sut.postEventProgress(eventId: "evt-1")
        #expect(result.isCompleted == true)
        #expect(result.chaptersCompleted == 20)
    }

    // MARK: - serverTimeOffset

    @Test("serverTimeOffset is zero when no Date header is present")
    func serverTimeOffsetDefault() async throws {
        let event = Self.makeEvent()
        let client = EventTestClient(event: event, progress: nil)
        let sut = SeasonalEventRepository(apiClient: client)
        _ = try await sut.fetchActiveEvent()
        let offset = await sut.serverTimeOffset
        #expect(offset == 0)
    }
}

// MARK: - SeasonalEventModel tests

@Suite("SeasonalEventModel")
@MainActor
struct SeasonalEventModelTests {

    // MARK: - countdownText formatting (via static formatCountdown)

    @Test("formatCountdown shows days when >= 1 day remaining")
    func countdownTextDays() {
        #expect(SeasonalEventModel.formatCountdown(seconds: 2 * 86_400 + 3 * 3_600 + 15 * 60) == "2d 3h 15m")
    }

    @Test("formatCountdown shows hours when < 1 day remaining")
    func countdownTextHours() {
        #expect(SeasonalEventModel.formatCountdown(seconds: 5 * 3_600 + 42 * 60 + 10) == "5h 42m 10s")
    }

    @Test("formatCountdown shows minutes and seconds when < 1 hour remaining")
    func countdownTextMinutes() {
        #expect(SeasonalEventModel.formatCountdown(seconds: 12 * 60 + 9) == "12m 9s")
    }

    @Test("formatCountdown shows 0m 0s when zero seconds remain")
    func countdownTextZero() {
        #expect(SeasonalEventModel.formatCountdown(seconds: 0) == "0m 0s")
    }

    @Test("formatCountdown clamps negative values to 0m 0s")
    func countdownTextNegative() {
        #expect(SeasonalEventModel.formatCountdown(seconds: -500) == "0m 0s")
    }

    // MARK: - Load states

    @Test("load transitions from .loading to .loaded")
    func loadTransitionsToLoaded() async throws {
        let event = makeEvent()
        let client = EventTestClient(event: event, progress: nil)
        let repo = SeasonalEventRepository(apiClient: client)
        let model = SeasonalEventModel(
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        model.load()
        // Allow async work to settle.
        try await Task.sleep(for: .milliseconds(100))
        guard case .loaded(let e, _) = model.loadState else {
            Issue.record("Expected .loaded, got \(model.loadState)")
            return
        }
        #expect(e?.eventId == "evt-1")
    }

    @Test("load transitions to .error on failure")
    func loadTransitionsToError() async throws {
        let client = FailingEventTestClient()
        let repo = SeasonalEventRepository(apiClient: client)
        let model = SeasonalEventModel(
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        model.load()
        try await Task.sleep(for: .milliseconds(100))
        guard case .error = model.loadState else {
            Issue.record("Expected .error, got \(model.loadState)")
            return
        }
    }

    // MARK: - Helpers

    private func makeEvent(hasJoined: Bool = false) -> SeasonalEvent {
        SeasonalEvent(
            eventId: "evt-1",
            title: "Summer Challenge",
            description: nil,
            startsAt: "2026-07-01T00:00:00Z",
            endsAt: "2026-07-31T23:59:59Z",
            targetChapters: 20,
            dailyTarget: 1,
            badge: nil,
            bonusIp: 0,
            isActive: true,
            hasJoined: hasJoined
        )
    }

}

// MARK: - Tolerant decoding

@Suite("SeasonalEvent tolerant decoding")
struct SeasonalEventDecodingTests {

    @Test("SeasonalEvent decodes successfully with all fields present")
    func decodesAllFields() throws {
        let json = """
        {
            "eventId": "evt-1",
            "title": "Summer Challenge",
            "description": "Read 20 chapters.",
            "startsAt": "2026-07-01T00:00:00Z",
            "endsAt": "2026-07-31T23:59:59Z",
            "targetChapters": 20,
            "dailyTarget": 1,
            "badge": null,
            "bonusIp": 300,
            "isActive": true,
            "hasJoined": false
        }
        """
        let event = try JSONDecoder.chapterFlow.decode(SeasonalEvent.self, from: Data(json.utf8))
        #expect(event.eventId == "evt-1")
        #expect(event.targetChapters == 20)
        #expect(event.badge == nil)
        #expect(event.hasJoined == false)
    }

    @Test("SeasonalEvent decodes with unknown extra fields (server evolution)")
    func decodesWithUnknownFields() throws {
        let json = """
        {
            "eventId": "evt-99",
            "title": "Future Event",
            "description": null,
            "startsAt": "2027-01-01T00:00:00Z",
            "endsAt": "2027-01-31T23:59:59Z",
            "targetChapters": 10,
            "dailyTarget": 1,
            "badge": null,
            "bonusIp": 0,
            "isActive": true,
            "hasJoined": false,
            "newFieldFromFutureServer": "should be ignored",
            "anotherUnknownField": 42
        }
        """
        let event = try JSONDecoder.chapterFlow.decode(SeasonalEvent.self, from: Data(json.utf8))
        #expect(event.eventId == "evt-99")
    }

    @Test("SeasonalEvent decodes optional description as nil when absent")
    func decodesOptionalDescriptionAbsent() throws {
        let json = """
        {
            "eventId": "evt-2",
            "title": "Minimal Event",
            "startsAt": "2026-07-01T00:00:00Z",
            "endsAt": "2026-07-31T23:59:59Z",
            "targetChapters": 5,
            "dailyTarget": 1,
            "badge": null,
            "bonusIp": 0,
            "isActive": true,
            "hasJoined": false
        }
        """
        let event = try JSONDecoder.chapterFlow.decode(SeasonalEvent.self, from: Data(json.utf8))
        #expect(event.description == nil)
    }

    @Test("EventProgress decodes with unknown extra fields")
    func eventProgressDecodesWithUnknownFields() throws {
        let json = """
        {
            "eventId": "evt-1",
            "chaptersCompleted": 7,
            "dailyChaptersCompleted": 1,
            "isCompleted": false,
            "joinedAt": "2026-07-03T08:00:00Z",
            "completedAt": null,
            "newFieldFromFuture": "ignored"
        }
        """
        let progress = try JSONDecoder.chapterFlow.decode(EventProgress.self, from: Data(json.utf8))
        #expect(progress.chaptersCompleted == 7)
        #expect(progress.isCompleted == false)
    }

    @Test("ActiveEventResponse decodes nil event gracefully")
    func activeEventResponseNilEvent() throws {
        let json = """
        { "event": null }
        """
        let response = try JSONDecoder.chapterFlow.decode(ActiveEventResponse.self, from: Data(json.utf8))
        #expect(response.event == nil)
    }

    @Test("ActiveEventResponse decodes missing event key gracefully")
    func activeEventResponseMissingEvent() throws {
        let json = """
        {}
        """
        // event is optional, so absent key decodes as nil
        let response = try? JSONDecoder.chapterFlow.decode(ActiveEventResponse.self, from: Data(json.utf8))
        #expect(response?.event == nil)
    }
}

// MARK: - Test doubles

// A simple class (not actor) to track call counts safely from tests.
final class EventTestClient: APIClientProtocol, @unchecked Sendable {
    private let event: SeasonalEvent?
    private let progress: EventProgress?

    var activeEventCallCount = 0
    var progressCallCount = 0

    init(event: SeasonalEvent?, progress: EventProgress?) {
        self.event = event
        self.progress = progress
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try makeResponseData(for: endpoint)
        return try JSONDecoder.chapterFlow.decode(T.self, from: data)
    }

    private func makeResponseData(for endpoint: Endpoint) throws -> Data {
        switch endpoint.path {
        case "/book/events/active":
            activeEventCallCount += 1
            return try JSONEncoder().encode(ActiveEventResponse(event: event))
        case let p where p.hasSuffix("/progress"):
            progressCallCount += 1
            let prog = progress ?? EventProgress(
                eventId: "evt-1", chaptersCompleted: 0,
                dailyChaptersCompleted: 0, isCompleted: false,
                joinedAt: nil, completedAt: nil
            )
            return try JSONEncoder().encode(EventProgressResponse(progress: prog))
        case let p where p.hasSuffix("/join"):
            let joined = event.map { ev in
                SeasonalEvent(
                    eventId: ev.eventId, title: ev.title,
                    description: ev.description,
                    startsAt: ev.startsAt, endsAt: ev.endsAt,
                    targetChapters: ev.targetChapters, dailyTarget: ev.dailyTarget,
                    badge: ev.badge, bonusIp: ev.bonusIp,
                    isActive: ev.isActive, hasJoined: true
                )
            }
            let initProgress = EventProgress(
                eventId: event?.eventId ?? "", chaptersCompleted: 0,
                dailyChaptersCompleted: 0, isCompleted: false,
                joinedAt: "2026-07-03T10:00:00Z", completedAt: nil
            )
            return try JSONEncoder().encode(JoinEventResponse(event: joined, progress: initProgress))
        default:
            throw AppError.notFound
        }
    }
}

final class FailingEventTestClient: APIClientProtocol, @unchecked Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        throw AppError.offline
    }
}
