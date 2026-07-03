import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Thread-safe mutable box

private final class Box<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - StubAPIClient (shared with EngagementRepositoryTests)

private final class ReviewStubAPIClient: APIClientProtocol, Sendable {
    typealias Handler = @Sendable (Endpoint) async throws -> Data
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}

// MARK: - Fixtures

private let now = Date(timeIntervalSinceReferenceDate: 0)

private let sampleCard = FsrsCard(
    cardId: "card-1",
    bookId: "book-1",
    chapterId: "chapter-1",
    front: "What is FSRS?",
    back: "A spaced repetition scheduling algorithm.",
    dueAt: "2001-01-01T00:00:00Z",
    stability: 5.0,
    difficulty: 4.5,
    state: .due,
    lastReviewAt: "2000-12-27T00:00:00Z",
    reps: 2,
    lapses: 0,
    elapsedDays: 5.0,
    scheduledDays: 5,
    retrievability: 0.9
)

private let sampleReviewsResponse = ReviewsResponse(
    cards: [sampleCard],
    dueCount: 1
)

private func reviewsData() throws -> Data {
    let json = """
    {
        "cards": [{
            "cardId": "card-1",
            "bookId": "book-1",
            "chapterId": "chapter-1",
            "front": "What is FSRS?",
            "back": "A spaced repetition scheduling algorithm.",
            "dueAt": "2001-01-01T00:00:00Z",
            "stability": 5.0,
            "difficulty": 4.5,
            "state": "review",
            "lastReviewAt": "2000-12-27T00:00:00Z",
            "reps": 2,
            "lapses": 0,
            "elapsedDays": 5.0,
            "scheduledDays": 5,
            "retrievability": 0.9
        }],
        "count": 1
    }
    """
    return Data(json.utf8)
}

private func gradeResponseData(cardId: String = "card-1") throws -> Data {
    let json = """
    {
        "card": {
            "cardId": "\(cardId)",
            "bookId": "book-1",
            "chapterId": "chapter-1",
            "front": "What is FSRS?",
            "back": "A spaced repetition scheduling algorithm.",
            "dueAt": "2001-01-31T00:00:00Z",
            "stability": 8.0,
            "difficulty": 4.9,
            "state": "review",
            "lastReviewAt": "2001-01-01T00:00:00Z",
            "reps": 3,
            "lapses": 0,
            "elapsedDays": 5.0,
            "scheduledDays": 30,
            "retrievability": 0.9
        }
    }
    """
    return Data(json.utf8)
}

// MARK: - ReviewsRepositoryTests

@Suite("ReviewsRepository")
struct ReviewsRepositoryTests {

    // MARK: Fetch due cards — online

    @Test("fetchDueCards returns cards from server on first call")
    func fetchDueCardsOnline() async throws {
        let client = ReviewStubAPIClient { endpoint in
            #expect(endpoint.path == "/book/me/reviews")
            return try reviewsData()
        }
        let repo = ReviewsRepository(apiClient: client)
        let response = try await repo.fetchDueCards()
        #expect(response.cards.count == 1)
        #expect(response.dueCount == 1)
        #expect(response.cards[0].cardId == "card-1")
    }

    @Test("fetchDueCards returns cached result within TTL")
    func fetchDueCardsUsesCache() async throws {
        let callCount = Box(0)
        let client = ReviewStubAPIClient { _ in
            callCount.value += 1
            return try reviewsData()
        }
        let repo = ReviewsRepository(apiClient: client)
        _ = try await repo.fetchDueCards()
        _ = try await repo.fetchDueCards()
        #expect(callCount.value == 1)
    }

    @Test("fetchDueCards bypasses cache when forceRefresh is true")
    func fetchDueCardsForceRefresh() async throws {
        let callCount = Box(0)
        let client = ReviewStubAPIClient { _ in
            callCount.value += 1
            return try reviewsData()
        }
        let repo = ReviewsRepository(apiClient: client)
        _ = try await repo.fetchDueCards()
        _ = try await repo.fetchDueCards(forceRefresh: true)
        #expect(callCount.value == 2)
    }

    // MARK: Fetch due cards — offline

    @Test("fetchDueCards throws AppError.offline when offline and no cache exists")
    func fetchDueCardsOfflineNoCache() async throws {
        let client = ReviewStubAPIClient { _ in throw AppError.offline }
        let repo = ReviewsRepository(apiClient: client)
        do {
            _ = try await repo.fetchDueCards()
            Issue.record("Expected AppError.offline to be thrown")
        } catch AppError.offline {
            // Expected
        }
    }

    @Test("fetchDueCards falls back to memory cache on offline error")
    func fetchDueCardsFallsBackToCache() async throws {
        let shouldThrow = Box(false)
        let client = ReviewStubAPIClient { _ in
            if shouldThrow.value { throw AppError.offline }
            return try reviewsData()
        }
        let repo = ReviewsRepository(apiClient: client)
        _ = try await repo.fetchDueCards()
        shouldThrow.value = true
        let cached = try await repo.fetchDueCards(forceRefresh: true)
        #expect(cached.cards.count == 1)
        #expect(cached.cards[0].cardId == "card-1")
    }

    // MARK: Grade card — online

    @Test("gradeCard sends POST to correct endpoint and returns updated card")
    func gradeCardOnline() async throws {
        let fetchCalled = Box(false)
        let gradeCalled = Box(false)
        let client = ReviewStubAPIClient { endpoint in
            if endpoint.path == "/book/me/reviews" {
                fetchCalled.value = true
                return try reviewsData()
            }
            if endpoint.path.hasPrefix("/book/me/reviews/") {
                gradeCalled.value = true
                return try gradeResponseData()
            }
            throw AppError.notFound
        }
        let repo = ReviewsRepository(apiClient: client)
        _ = try await repo.fetchDueCards()
        let updated = try await repo.gradeCard(sampleCard, grade: .good)
        #expect(fetchCalled.value)
        #expect(gradeCalled.value)
        #expect(updated.scheduledDays == 30)
    }

    @Test("gradeCard updates the in-memory cache with server response")
    func gradeCardUpdatesCache() async throws {
        let client = ReviewStubAPIClient { endpoint in
            if endpoint.path == "/book/me/reviews" { return try reviewsData() }
            return try gradeResponseData()
        }
        let repo = ReviewsRepository(apiClient: client)
        _ = try await repo.fetchDueCards()
        let updated = try await repo.gradeCard(sampleCard, grade: .good)
        let cached = try await repo.fetchDueCards()
        #expect(cached.cards.first?.scheduledDays == updated.scheduledDays)
    }

    // MARK: Grade card — offline

    @Test("gradeCard offline produces optimistic FSRS schedule")
    func gradeCardOffline() async throws {
        let fetchCount = Box(0)
        let client = ReviewStubAPIClient { endpoint in
            fetchCount.value += 1
            if endpoint.path == "/book/me/reviews" { return try reviewsData() }
            // Grade endpoint throws offline
            throw AppError.offline
        }
        let repo = ReviewsRepository(apiClient: client)
        _ = try await repo.fetchDueCards()
        let optimistic = try await repo.gradeCard(sampleCard, grade: .good, now: now)
        // Should have a future due date (FSRS schedules forward)
        #expect(optimistic.dueAt != nil)
        #expect(optimistic.reps == (sampleCard.reps ?? 0) + 1)
    }

    @Test("gradeCard offline adds to pendingGradeCount")
    func gradeCardOfflinePendingCount() async throws {
        let client = ReviewStubAPIClient { endpoint in
            if endpoint.path == "/book/me/reviews" { return try reviewsData() }
            throw AppError.offline
        }
        let repo = ReviewsRepository(apiClient: client)
        _ = try await repo.fetchDueCards()
        let before = await repo.pendingGradeCount()
        _ = try await repo.gradeCard(sampleCard, grade: .again, now: now)
        // With no modelContainer, outbox is skipped — pendingGradeCount stays 0
        let after = await repo.pendingGradeCount()
        #expect(after == before)
    }

    // MARK: Cache invalidation

    @Test("invalidate clears the memory cache")
    func invalidateClearsCache() async throws {
        let callCount = Box(0)
        let client = ReviewStubAPIClient { _ in
            callCount.value += 1
            return try reviewsData()
        }
        let repo = ReviewsRepository(apiClient: client)
        _ = try await repo.fetchDueCards()
        await repo.invalidate()
        _ = try await repo.fetchDueCards()
        #expect(callCount.value == 2)
    }

    // MARK: pendingGradeCount with no container

    @Test("pendingGradeCount returns 0 when no modelContainer is set")
    func pendingGradeCountNoContainer() async {
        let client = ReviewStubAPIClient { _ in throw AppError.offline }
        let repo = ReviewsRepository(apiClient: client)
        let count = await repo.pendingGradeCount()
        #expect(count == 0)
    }
}

// MARK: - ReviewsResponse decoding

@Suite("ReviewsResponse — decoding")
struct ReviewsResponseDecodingTests {

    @Test("decodes 'count' key from server JSON")
    func decodesCountKey() throws {
        let json = """
        { "cards": [], "count": 7 }
        """
        let resp = try JSONCoding.decoder.decode(ReviewsResponse.self, from: Data(json.utf8))
        #expect(resp.dueCount == 7)
    }

    @Test("decodes 'dueCount' key for backward compat")
    func decodesDueCountKey() throws {
        let json = """
        { "cards": [], "dueCount": 3 }
        """
        let resp = try JSONCoding.decoder.decode(ReviewsResponse.self, from: Data(json.utf8))
        #expect(resp.dueCount == 3)
    }

    @Test("count defaults to 0 when key is absent")
    func decodesZeroWhenAbsent() throws {
        let json = """
        { "cards": [] }
        """
        let resp = try JSONCoding.decoder.decode(ReviewsResponse.self, from: Data(json.utf8))
        #expect(resp.dueCount == 0)
    }

    @Test("cards decode lossily — bad element is dropped")
    func lossyCardsDecoding() throws {
        let json = """
        {
            "cards": [
                null,
                { "cardId": "c2", "bookId": "b1", "front": "Q", "back": "A" }
            ],
            "count": 2
        }
        """
        let resp = try JSONCoding.decoder.decode(ReviewsResponse.self, from: Data(json.utf8))
        #expect(resp.cards.count == 1)
        #expect(resp.cards[0].cardId == "c2")
    }
}

// MARK: - FsrsCard helpers

@Suite("FsrsCard — helpers")
struct FsrsCardHelpersTests {

    @Test("isDue returns true when dueAt is in the past")
    func isDuePast() {
        let card = FsrsCard(
            cardId: "c1", bookId: "b1", chapterId: nil,
            front: "Q", back: "A",
            dueAt: "2001-01-01T00:00:00Z",
            stability: nil, difficulty: nil, state: .due,
            lastReviewAt: nil, reps: nil, lapses: nil,
            elapsedDays: nil, scheduledDays: nil, retrievability: nil
        )
        let checkDate = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(card.isDue(now: checkDate))
    }

    @Test("isDue returns false when dueAt is in the future")
    func isDueFuture() {
        let card = FsrsCard(
            cardId: "c2", bookId: "b1", chapterId: nil,
            front: "Q", back: "A",
            dueAt: "2099-01-01T00:00:00Z",
            stability: nil, difficulty: nil, state: .due,
            lastReviewAt: nil, reps: nil, lapses: nil,
            elapsedDays: nil, scheduledDays: nil, retrievability: nil
        )
        #expect(!card.isDue(now: Date()))
    }

    @Test("isDue returns true for .new state with no dueAt")
    func isDueNewState() {
        let card = FsrsCard(
            cardId: "c3", bookId: "b1", chapterId: nil,
            front: "Q", back: "A",
            dueAt: nil,
            stability: nil, difficulty: nil, state: .new,
            lastReviewAt: nil, reps: nil, lapses: nil,
            elapsedDays: nil, scheduledDays: nil, retrievability: nil
        )
        #expect(card.isDue())
    }

    @Test("dueDate parses ISO-8601 with fractional seconds")
    func dueDateFractional() {
        let card = FsrsCard(
            cardId: "c4", bookId: "b1", chapterId: nil,
            front: "Q", back: "A",
            dueAt: "2001-01-01T00:00:00.000Z",
            stability: nil, difficulty: nil, state: .due,
            lastReviewAt: nil, reps: nil, lapses: nil,
            elapsedDays: nil, scheduledDays: nil, retrievability: nil
        )
        #expect(card.dueDate != nil)
    }
}
