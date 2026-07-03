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
/// - Schedule local due-notifications via ``ReviewNotificationScheduler``.
///
/// The actor serialises all reads/writes; callers do not need additional locking.
public actor ReviewsRepository {

    // MARK: Dependencies

    private let apiClient: any APIClientProtocol
    private let modelContainer: ModelContainer?

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

    public init(apiClient: some APIClientProtocol, modelContainer: ModelContainer? = nil) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
    }

    // MARK: - Fetch due cards

    /// Returns the user's due review cards.
    ///
    /// - Online: fetches `GET /book/me/reviews`, caches the result, schedules notifications.
    /// - Offline: returns the last cached response (memory → disk → `AppError.offline`).
    ///
    /// Before fetching, syncs any pending offline grades so the server sees the
    /// most recent state before returning a fresh deck.
    public func fetchDueCards(forceRefresh: Bool = false) async throws -> ReviewsResponse {
        await syncPendingGrades()

        if !forceRefresh, let entry = memCache, !entry.isStale(ttl: cacheTTL) {
            return entry.response
        }

        do {
            let resp: ReviewsResponse = try await apiClient.send(Endpoints.getReviews())
            memCache = MemEntry(response: resp, storedAt: Date())
            persistToDisk(resp)
            #if os(iOS)
            await ReviewNotificationScheduler.shared.scheduleNotifications(for: resp.cards)
            #endif
            return resp
        } catch AppError.offline {
            if let cached: ReviewsCacheEnvelope = loadFromDisk() {
                let resp = cached.toResponse()
                memCache = MemEntry(response: resp, storedAt: Date())
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
        do {
            let endpoint = try Endpoints.gradeReviewCard(cardId: card.cardId, rating: grade.rawValue)
            let resp: ReviewCardResponse = try await apiClient.send(endpoint)
            replaceInCache(resp.card)
            return resp.card
        } catch AppError.offline {
            return await gradeOffline(card, grade: grade, now: now)
        }
    }

    // MARK: - Offline grading

    private func gradeOffline(_ card: FsrsCard, grade: FSRSGrade, now: Date) async -> FsrsCard {
        let input  = FSRSScheduleInput(card: card)
        let result = FSRSScheduler.schedule(input: input, grade: grade, now: now)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dueStr = isoFormatter.string(from: result.nextDueDate)
        let nowStr  = isoFormatter.string(from: now)

        // Persist to outbox
        queuePendingGrade(PendingReviewGrade(
            cardId: card.cardId,
            rating: grade.rawValue,
            reviewedAt: nowStr,
            optimisticStability: result.stability,
            optimisticDifficulty: result.difficulty,
            optimisticDueAt: dueStr
        ))

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
        replaceInCache(optimistic)
        return optimistic
    }

    private func queuePendingGrade(_ pending: PendingReviewGrade) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        context.insert(pending)
        do { try context.save() } catch {
            log.warning("Failed to queue offline review grade for \(pending.cardId): \(error)")
        }
    }

    // MARK: - Sync pending grades

    /// Replays offline-queued grades to the server. Server schedule wins on any conflict.
    func syncPendingGrades() async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PendingReviewGrade>(
            sortBy: [SortDescriptor(\.nextRetryAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        let now = Date()
        for entry in pending where entry.nextRetryAt <= now {
            do {
                let endpoint = try Endpoints.gradeReviewCard(cardId: entry.cardId, rating: entry.rating)
                let resp: ReviewCardResponse = try await apiClient.send(endpoint)
                replaceInCache(resp.card)
                context.delete(entry)
                log.info("Synced offline review grade for card \(entry.cardId)")
            } catch AppError.offline {
                break
            } catch {
                entry.retryCount += 1
                if entry.retryCount >= 3 {
                    log.error("Discarding failed grade for \(entry.cardId) after 3 attempts: \(error)")
                    context.delete(entry)
                } else {
                    entry.nextRetryAt = Date().addingTimeInterval(Double(entry.retryCount) * 60)
                }
            }
        }
        try? context.save()
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
