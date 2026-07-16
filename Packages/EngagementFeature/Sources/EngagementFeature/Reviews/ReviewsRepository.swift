import Foundation
import CoreKit
import Models
import Networking
import Persistence
import SwiftData
import OSLog

private let log = Logger(subsystem: "com.chapterflow.engagement", category: "reviews")

// MARK: - Cache key

private let reviewsCacheKey = "engagement.reviews"

// MARK: - Disk-cache envelope

/// Thin Codable wrapper that round-trips `ReviewsResponse` through SwiftData's
/// JSON blob cache without re-implementing the custom `init(from:)` decoder.
private struct ReviewsCacheEnvelope: Codable {
    let cards: [FsrsCard]
    let dueCount: Int

    init(_ response: ReviewsResponse) {
        self.cards    = response.cards
        self.dueCount = response.dueCount
    }

    func toResponse() -> ReviewsResponse {
        ReviewsResponse(cards: cards, dueCount: dueCount)
    }
}

// MARK: - ReviewsRepository

/// Data layer for the FSRS spaced-repetition reviews feature.
///
/// Responsibilities:
/// - Fetch due cards from `GET /book/me/reviews` with local SwiftData caching.
/// - Submit grades via `POST /book/me/reviews/{cardId}` with an offline outbox.
/// - Update the local schedule optimistically (server wins on reconciliation).
///
/// Local review-notification scheduling is intentionally disabled until its
/// requests have an account-scoped owner. A process-global scheduler can race
/// session teardown and surface account A's private state after account B signs
/// in. ``ReviewNotificationScheduler`` remains available for irreversible
/// boundary cleanup only.
///
/// The actor serialises all reads/writes; callers do not need additional locking.
public actor ReviewsRepository {

    // MARK: Dependencies

    private let apiClient: any APIClientProtocol
    private let modelContainer: ModelContainer?
    private let workPermit: SessionWorkPermit

    // MARK: In-memory cache

    private struct MemEntry {
        var response: ReviewsResponse
        let storedAt: Date
        func isStale(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(storedAt) >= ttl
        }
    }

    private var memCache: MemEntry?
    private let cacheTTL: TimeInterval = 5 * 60

    // MARK: Init

    public init(
        apiClient: some APIClientProtocol,
        modelContainer: ModelContainer? = nil,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
        self.workPermit = workPermit
    }

    // MARK: - Fetch due cards

    /// Returns the user's due review cards.
    ///
    /// - Online: fetches `GET /book/me/reviews` and caches the result.
    /// - Offline: returns the last cached response (memory → disk → `AppError.offline`).
    ///
    /// Before fetching, syncs any pending offline grades so the server sees the
    /// most recent state before returning a fresh deck.
    public func fetchDueCards(forceRefresh: Bool = false) async throws -> ReviewsResponse {
        let ticket = try workPermit.begin()
        await syncPendingGrades(ticket: ticket)
        try workPermit.validate(ticket)

        if !forceRefresh, let entry = memCache, !entry.isStale(ttl: cacheTTL) {
            return entry.response
        }

        do {
            let resp: ReviewsResponse = try await apiClient.send(Endpoints.getReviews())
            try workPermit.commit(ticket) {
                memCache = MemEntry(response: resp, storedAt: Date())
                persistToDisk(resp)
            }
            return resp
        } catch AppError.offline {
            try workPermit.validate(ticket)
            if let cached: ReviewsCacheEnvelope = loadFromDisk() {
                let resp = cached.toResponse()
                try workPermit.commit(ticket) {
                    memCache = MemEntry(response: resp, storedAt: Date())
                }
                return resp
            }
            if let entry = memCache { return entry.response }
            throw AppError.offline
        }
    }

    // MARK: - Grade a card

    /// Submits a review grade for a single card.
    ///
    /// - Online: `POST /book/me/reviews/{cardId}` → server-authoritative result.
    /// - Offline: queues the grade in the SwiftData outbox and applies an optimistic
    ///   FSRS schedule locally. The server result wins when synced.
    ///
    /// - Returns: The updated card (server-authoritative or optimistic).
    @discardableResult
    public func gradeCard(_ card: FsrsCard, grade: FSRSGrade, now: Date = Date()) async throws -> FsrsCard {
        let ticket = try workPermit.begin()
        do {
            let endpoint = try Endpoints.gradeReviewCard(cardId: card.cardId, rating: grade.rawValue)
            let resp: ReviewCardResponse = try await apiClient.send(endpoint)
            try workPermit.commit(ticket) {
                replaceInCache(resp.card)
            }
            return resp.card
        } catch AppError.offline {
            return try await gradeOffline(card, grade: grade, now: now, ticket: ticket)
        }
    }

    // MARK: - Offline grading

    private func gradeOffline(
        _ card: FsrsCard,
        grade: FSRSGrade,
        now: Date,
        ticket: UInt64
    ) async throws -> FsrsCard {
        let input  = FSRSScheduleInput(card: card)
        let result = FSRSScheduler.schedule(input: input, grade: grade, now: now)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dueStr = isoFormatter.string(from: result.nextDueDate)
        let nowStr  = isoFormatter.string(from: now)

        // Persist to outbox
        let pending = PendingReviewGrade(
            cardId: card.cardId,
            rating: grade.rawValue,
            reviewedAt: nowStr,
            optimisticStability: result.stability,
            optimisticDifficulty: result.difficulty,
            optimisticDueAt: dueStr
        )

        // Build optimistic card
        let optimistic = FsrsCard(
            cardId: card.cardId,
            bookId: card.bookId,
            chapterId: card.chapterId,
            front: card.front,
            back: card.back,
            dueAt: dueStr,
            stability: result.stability,
            difficulty: result.difficulty,
            state: result.newState,
            lastReviewAt: nowStr,
            reps: (card.reps ?? 0) + 1,
            lapses: result.lapses,
            elapsedDays: result.elapsedDays,
            scheduledDays: result.scheduledDays,
            retrievability: nil
        )
        try workPermit.commit(ticket) {
            try queuePendingGrade(pending)
            replaceInCache(optimistic)
        }
        return optimistic
    }

    private func queuePendingGrade(_ pending: PendingReviewGrade) throws {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        context.insert(pending)
        try context.save()
    }

    // MARK: - Sync pending grades

    /// Replays offline-queued grades to the server. Server schedule wins on any conflict.
    private func syncPendingGrades(ticket: UInt64) async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PendingReviewGrade>(
            sortBy: [SortDescriptor(\.nextRetryAt)]
        )
        guard let pendingRows = try? context.fetch(descriptor), !pendingRows.isEmpty else { return }
        let pending = pendingRows.map {
            PendingGradeSnapshot(
                uploadID: $0.uploadId,
                cardID: $0.cardId,
                rating: $0.rating,
                nextRetryAt: $0.nextRetryAt
            )
        }

        let now = Date()
        for entry in pending where entry.nextRetryAt <= now {
            do {
                let endpoint = try Endpoints.gradeReviewCard(cardId: entry.cardID, rating: entry.rating)
                let resp: ReviewCardResponse = try await apiClient.send(endpoint)
                try workPermit.commit(ticket) {
                    replaceInCache(resp.card)
                    try deletePendingGrade(uploadID: entry.uploadID, container: container)
                }
                log.info("Synced offline review grade for card \(entry.cardID)")
            } catch is CancellationError {
                return
            } catch AppError.offline {
                break
            } catch {
                do {
                    try workPermit.commit(ticket) {
                        try recordRetry(uploadID: entry.uploadID, container: container)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    log.warning("Failed to persist review retry state")
                }
            }
        }
    }

    private struct PendingGradeSnapshot: Sendable {
        let uploadID: String
        let cardID: String
        let rating: Int
        let nextRetryAt: Date
    }

    private func deletePendingGrade(uploadID: String, container: ModelContainer) throws {
        let context = ModelContext(container)
        let identifier = uploadID
        let descriptor = FetchDescriptor<PendingReviewGrade>(
            predicate: #Predicate { $0.uploadId == identifier }
        )
        if let row = try context.fetch(descriptor).first {
            context.delete(row)
            try context.save()
        }
    }

    private func recordRetry(uploadID: String, container: ModelContainer) throws {
        let context = ModelContext(container)
        let identifier = uploadID
        let descriptor = FetchDescriptor<PendingReviewGrade>(
            predicate: #Predicate { $0.uploadId == identifier }
        )
        guard let row = try context.fetch(descriptor).first else { return }
        row.retryCount += 1
        let delay = min(pow(2.0, Double(row.retryCount)) * 30, 3_600)
        row.nextRetryAt = Date().addingTimeInterval(delay)
        try context.save()
    }

    /// Count of grades waiting in the offline outbox.
    public func pendingGradeCount() -> Int {
        guard let container = modelContainer else { return 0 }
        let context = ModelContext(container)
        return (try? context.fetchCount(FetchDescriptor<PendingReviewGrade>())) ?? 0
    }

    // MARK: - Cache management

    private func replaceInCache(_ updated: FsrsCard) {
        guard var entry = memCache else { return }
        var cards = entry.response.cards
        if let idx = cards.firstIndex(where: { $0.cardId == updated.cardId }) {
            cards[idx] = updated
        }
        let dueCount = cards.filter { $0.isDue() }.count
        entry.response = ReviewsResponse(cards: cards, dueCount: dueCount)
        memCache = entry
        persistToDisk(entry.response)
    }

    private func persistToDisk(_ response: ReviewsResponse) {
        guard let container = modelContainer else { return }
        guard let data = try? JSONCoding.encoder.encode(ReviewsCacheEnvelope(response)),
              let json = String(data: data, encoding: .utf8) else { return }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == reviewsCacheKey }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.value = json
            existing.updatedAt = Date()
        } else {
            context.insert(CachedKeyValue(key: reviewsCacheKey, value: json))
        }
        try? context.save()
    }

    private func loadFromDisk() -> ReviewsCacheEnvelope? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == reviewsCacheKey }
        )
        descriptor.fetchLimit = 1
        guard let entry = (try? context.fetch(descriptor))?.first,
              let data = entry.value.data(using: .utf8) else { return nil }
        return try? JSONCoding.decoder.decode(ReviewsCacheEnvelope.self, from: data)
    }

    // MARK: - Cache invalidation

    public func invalidate() {
        memCache = nil
    }
}
