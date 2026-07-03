import Testing
import Foundation
@testable import EngagementFeature
import Models
import CoreKit
import Networking

// MARK: - JourneysRepository tests

@Suite("JourneysRepository")
struct JourneysRepositoryTests {

    // MARK: Fixtures

    private static func makeJourney(id: String = "j-1") -> JourneyCatalogItem {
        JourneyCatalogItem(
            journeyId: id,
            title: "Test Journey",
            description: "A test journey.",
            durationWeeks: 4,
            books: [
                JourneyBookEntry(
                    bookId: "b-1", title: "Book One", author: nil,
                    cover: nil, reason: nil, order: 0
                ),
                JourneyBookEntry(
                    bookId: "b-2", title: "Book Two", author: nil,
                    cover: nil, reason: nil, order: 1
                ),
            ],
            completionBadge: nil,
            bonusFlowPoints: 100,
            gradient: nil
        )
    }

    private static func makeUserJourney(id: String = "j-1", completed: Bool = false) -> UserJourney {
        UserJourney(
            journeyId: id,
            currentBookIndex: completed ? 2 : 0,
            completedBookIds: completed ? ["b-1", "b-2"] : [],
            isCompleted: completed,
            startedAt: "2026-06-01T10:00:00Z",
            completedAt: completed ? "2026-07-01T10:00:00Z" : nil
        )
    }

    // MARK: - fetchJourneys

    @Test("fetchJourneys returns catalog from server")
    func fetchJourneysSuccess() async throws {
        let journey = Self.makeJourney()
        let client = JourneysTestClient(journeys: [journey], userJourney: nil)
        let sut = JourneysRepository(apiClient: client)
        let result = try await sut.fetchJourneys()
        #expect(result.count == 1)
        #expect(result.first?.journeyId == "j-1")
    }

    @Test("fetchJourneys uses memory cache on second call")
    func fetchJourneysCachesResult() async throws {
        let journey = Self.makeJourney()
        let client = JourneysTestClient(journeys: [journey], userJourney: nil)
        let sut = JourneysRepository(apiClient: client)
        _ = try await sut.fetchJourneys()
        _ = try await sut.fetchJourneys()
        let callCount = await client.journeysCallCount
        // Cache hit means only 1 network call
        #expect(callCount == 1)
    }

    @Test("fetchJourneys forceRefresh bypasses cache")
    func fetchJourneysForceRefresh() async throws {
        let journey = Self.makeJourney()
        let client = JourneysTestClient(journeys: [journey], userJourney: nil)
        let sut = JourneysRepository(apiClient: client)
        _ = try await sut.fetchJourneys()
        _ = try await sut.fetchJourneys(forceRefresh: true)
        let callCount = await client.journeysCallCount
        #expect(callCount == 2)
    }

    @Test("fetchJourneys offline with no cache throws offline error")
    func fetchJourneysOfflineNoCache() async throws {
        let client = OfflineTestClient()
        let sut = JourneysRepository(apiClient: client)
        do {
            _ = try await sut.fetchJourneys()
            Issue.record("Expected offline error to be thrown")
        } catch AppError.offline {
            // expected
        }
    }

    // MARK: - fetchUserJourney

    @Test("fetchUserJourney returns enrollment from server")
    func fetchUserJourneySuccess() async throws {
        let uj = Self.makeUserJourney()
        let client = JourneysTestClient(journeys: [], userJourney: uj)
        let sut = JourneysRepository(apiClient: client)
        let result = try await sut.fetchUserJourney(id: "j-1")
        #expect(result.journeyId == "j-1")
        #expect(!result.isCompleted)
    }

    @Test("fetchUserJourney propagates notFound for unenrolled user")
    func fetchUserJourneyNotFound() async throws {
        let client = OfflineTestClient(error: .notFound)
        let sut = JourneysRepository(apiClient: client)
        do {
            _ = try await sut.fetchUserJourney(id: "j-1")
            Issue.record("Expected notFound error to be thrown")
        } catch AppError.notFound {
            // expected
        }
    }

    // MARK: - startJourney

    @Test("startJourney posts and returns new enrollment")
    func startJourneySuccess() async throws {
        let uj = Self.makeUserJourney()
        let client = JourneysTestClient(journeys: [], userJourney: uj)
        let sut = JourneysRepository(apiClient: client)
        let result = try await sut.startJourney(id: "j-1")
        #expect(result.journeyId == "j-1")
        #expect(result.currentBookIndex == 0)
    }

    // MARK: - invalidate

    @Test("invalidate clears memory cache, forcing refetch")
    func invalidateClearsCache() async throws {
        let journey = Self.makeJourney()
        let client = JourneysTestClient(journeys: [journey], userJourney: nil)
        let sut = JourneysRepository(apiClient: client)
        _ = try await sut.fetchJourneys()
        await sut.invalidate()
        _ = try await sut.fetchJourneys()
        let callCount = await client.journeysCallCount
        #expect(callCount == 2)
    }
}

// MARK: - JourneyDetailModel tests

@Suite("JourneyDetailModel")
@MainActor
struct JourneyDetailModelTests {

    private static func makeJourney() -> JourneyCatalogItem {
        JourneyCatalogItem(
            journeyId: "j-1",
            title: "Test",
            description: "Desc",
            durationWeeks: 4,
            books: [
                JourneyBookEntry(bookId: "b-1", title: "Book 1", author: nil, cover: nil, reason: nil, order: 0),
                JourneyBookEntry(bookId: "b-2", title: "Book 2", author: nil, cover: nil, reason: nil, order: 1),
            ],
            completionBadge: JourneyBadge(badgeId: "badge-1", name: "Gold", icon: "🏆"),
            bonusFlowPoints: 200,
            gradient: nil
        )
    }

    @Test("initial state is .loading")
    func initialState() {
        let repo = JourneysRepository(apiClient: OfflineTestClient())
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        if case .loading = model.loadState { } else {
            Issue.record("Expected .loading, got \(model.loadState)")
        }
    }

    @Test("isEnrolled and progressFraction are zero before load")
    func beforeLoadDefaults() {
        let repo = JourneysRepository(apiClient: OfflineTestClient())
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        #expect(!model.isEnrolled)
        #expect(model.progressFraction == 0)
        #expect(model.activeBook == nil)
    }

    @Test("refresh sets notStarted on 404")
    func refreshSetsNotStartedOn404() async throws {
        let repo = JourneysRepository(apiClient: OfflineTestClient(error: .notFound))
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        await model.refresh()
        if case .notStarted = model.loadState { } else {
            Issue.record("Expected .notStarted, got \(model.loadState)")
        }
    }

    @Test("refresh sets error state on generic failure")
    func refreshSetsErrorState() async throws {
        let repo = JourneysRepository(apiClient: OfflineTestClient(error: .offline))
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        await model.refresh()
        if case .error = model.loadState { } else {
            Issue.record("Expected .error, got \(model.loadState)")
        }
    }

    @Test("activeBook returns entry at currentBookIndex")
    func activeBookReturnsCorrectEntry() async throws {
        let uj = UserJourney(
            journeyId: "j-1", currentBookIndex: 1,
            completedBookIds: ["b-1"], isCompleted: false,
            startedAt: nil, completedAt: nil
        )
        let repo = JourneysRepository(apiClient: JourneysTestClient(journeys: [], userJourney: uj))
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        await model.refresh()
        #expect(model.activeBook?.bookId == "b-2")
    }

    @Test("progressFraction is 0.5 when one of two books completed")
    func progressFractionHalfDone() async throws {
        let uj = UserJourney(
            journeyId: "j-1", currentBookIndex: 1,
            completedBookIds: ["b-1"], isCompleted: false,
            startedAt: nil, completedAt: nil
        )
        let repo = JourneysRepository(apiClient: JourneysTestClient(journeys: [], userJourney: uj))
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        await model.refresh()
        #expect(abs(model.progressFraction - 0.5) < 0.001)
    }

    @Test("completedBookIds reflects server state")
    func completedBookIdsMatchServer() async throws {
        let uj = UserJourney(
            journeyId: "j-1", currentBookIndex: 1,
            completedBookIds: ["b-1"], isCompleted: false,
            startedAt: nil, completedAt: nil
        )
        let repo = JourneysRepository(apiClient: JourneysTestClient(journeys: [], userJourney: uj))
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        await model.refresh()
        #expect(model.completedBookIds == ["b-1"])
    }

    @Test("completion celebration fires on first completed load")
    func completionCelebrationFiresOnce() async throws {
        let uj = UserJourney(
            journeyId: "j-1", currentBookIndex: 2,
            completedBookIds: ["b-1", "b-2"], isCompleted: true,
            startedAt: nil, completedAt: "2026-07-03T00:00:00Z"
        )
        let repo = JourneysRepository(apiClient: JourneysTestClient(journeys: [], userJourney: uj))
        let presenter = CelebrationPresenter()
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: presenter,
            userDefaults: defaults
        )
        await model.refresh()
        #expect(model.isCompleted)
        // Celebration should have been enqueued and presented
        #expect(presenter.currentEvent != nil)
        if case .journeyComplete(let title) = presenter.currentEvent {
            #expect(title == "Test")
        } else {
            Issue.record("Expected .journeyComplete event")
        }
    }

    @Test("completion celebration does not fire when already seen")
    func completionCelebrationSkippedWhenSeen() async throws {
        let uj = UserJourney(
            journeyId: "j-1", currentBookIndex: 2,
            completedBookIds: ["b-1", "b-2"], isCompleted: true,
            startedAt: nil, completedAt: "2026-07-03T00:00:00Z"
        )
        let repo = JourneysRepository(apiClient: JourneysTestClient(journeys: [], userJourney: uj))
        let presenter = CelebrationPresenter()
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        // Pre-seed to simulate that celebration already fired once
        defaults.set(true, forKey: "com.chapterflow.journey.completion.j-1")
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: presenter,
            userDefaults: defaults
        )
        await model.refresh()
        #expect(model.isCompleted)
        // Presenter should remain idle
        #expect(presenter.currentEvent == nil)
    }

    @Test("isCompleted false for in-progress journey")
    func isCompletedFalseForInProgress() async throws {
        let uj = UserJourney(
            journeyId: "j-1", currentBookIndex: 0,
            completedBookIds: [], isCompleted: false,
            startedAt: nil, completedAt: nil
        )
        let repo = JourneysRepository(apiClient: JourneysTestClient(journeys: [], userJourney: uj))
        let model = JourneyDetailModel(
            journey: Self.makeJourney(),
            repository: repo,
            celebrationPresenter: CelebrationPresenter()
        )
        await model.refresh()
        #expect(!model.isCompleted)
    }
}

// MARK: - Test helpers

/// Happy-path API client that returns canned journeys catalog and/or user journey.
private actor JourneysTestClient: APIClientProtocol {
    private let journeys: [JourneyCatalogItem]
    private let userJourney: UserJourney?
    private(set) var journeysCallCount = 0

    init(journeys: [JourneyCatalogItem], userJourney: UserJourney?) {
        self.journeys = journeys
        self.userJourney = userJourney
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        if endpoint.path == "/book/books/journeys" {
            journeysCallCount += 1
            let data = try JSONCoding.encoder.encode(JourneysListResponse(journeys: journeys))
            return try JSONCoding.decoder.decode(T.self, from: data)
        }
        if endpoint.path.hasPrefix("/book/me/journeys/") {
            guard let uj = userJourney else { throw AppError.notFound }
            let data = try JSONCoding.encoder.encode(UserJourneyResponse(journey: uj))
            return try JSONCoding.decoder.decode(T.self, from: data)
        }
        throw AppError.notFound
    }
}

/// Always throws a specified error — used to test error/offline paths.
private struct OfflineTestClient: APIClientProtocol {
    let error: AppError
    init(error: AppError = .offline) { self.error = error }
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        throw error
    }
}
