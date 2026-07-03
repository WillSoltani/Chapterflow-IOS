import Foundation
import CoreKit
import Models
import Networking
import Persistence
import SwiftData
import OSLog

private let log = Logger(subsystem: "com.chapterflow.engagement", category: "scenarios")

// MARK: - ScenarioRepository

/// Manages scenario submissions for the apply-it axis.
///
/// Endpoints:
/// - `GET  /book/me/books/{bookId}/chapters/{n}/scenarios`
/// - `POST /book/me/books/{bookId}/chapters/{n}/scenarios`
///
/// Offline submissions are queued in the SwiftData outbox (`PendingScenarioUpload`)
/// and synced on reconnect. Status and points are server-authoritative — never
/// granted client-side.
public actor ScenarioRepository {

    // MARK: Dependencies

    private let apiClient: any APIClientProtocol
    private let modelContainer: ModelContainer?

    // MARK: In-memory cache (keyed by "bookId/chapterNumber")

    private var memCache: [String: ScenariosResponse] = [:]

    // MARK: Init

    public init(apiClient: some APIClientProtocol, modelContainer: ModelContainer? = nil) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
    }

    // MARK: - Public: Fetch

    /// Fetches the user's and (if exposed) community scenarios for a chapter.
    ///
    /// Falls back to in-memory cache when offline; throws `.offline` only when no
    /// cached data exists.
    public func fetchScenarios(
        bookId: String,
        chapterNumber: Int,
        forceRefresh: Bool = false
    ) async throws -> ScenariosResponse {
        let key = cacheKey(bookId: bookId, chapterNumber: chapterNumber)
        if !forceRefresh, let cached = memCache[key] {
            return cached
        }
        do {
            let resp: ScenariosResponse = try await apiClient.send(
                Endpoints.getScenarios(bookId: bookId, chapterNumber: chapterNumber)
            )
            let merged = mergeWithPendingLocals(serverResp: resp, bookId: bookId, chapterNumber: chapterNumber)
            memCache[key] = merged
            return merged
        } catch AppError.offline {
            if let cached = memCache[key] { return cached }
            throw AppError.offline
        }
    }

    // MARK: - Public: Submit

    /// Submits a new scenario for a chapter.
    ///
    /// - On success: returns the server-authoritative `UserScenario` (pending status).
    /// - Offline: enqueues the submission in the SwiftData outbox and returns a local
    ///   placeholder. Status is always `.pending`; points are never granted locally.
    public func submitScenario(
        bookId: String,
        chapterNumber: Int,
        body: ScenarioPostBody,
        scope: ScenarioScope
    ) async throws -> UserScenario {
        let endpoint = try Endpoints.postScenario(bookId: bookId, chapterNumber: chapterNumber, body: body)
        do {
            let resp: ScenarioResponse = try await apiClient.send(endpoint)
            let created = resp.scenario
            upsertMemory(created, bookId: bookId, chapterNumber: chapterNumber)
            return created
        } catch AppError.offline {
            let local = makeLocalScenario(bookId: bookId, chapterNumber: chapterNumber, body: body, scope: scope)
            upsertMemory(local, bookId: bookId, chapterNumber: chapterNumber)
            enqueueUpload(local: local, endpoint: endpoint)
            return local
        }
    }

    // MARK: - Public: Sync outbox

    /// Replays all pending scenario uploads. Call when connectivity is restored.
    ///
    /// Successfully synced entries are removed from the outbox. Failed entries are
    /// back-offed with exponential delay.
    public func syncPendingUploads() async {
        guard let container = modelContainer else { return }
        let ctx = ModelContext(container)
        let now = Date()
        var descriptor = FetchDescriptor<PendingScenarioUpload>(
            predicate: #Predicate { $0.nextRetryAt <= now }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        guard let pending = try? ctx.fetch(descriptor) else { return }

        for ticket in pending {
            guard let bodyData = ticket.requestJSON.data(using: .utf8) else { continue }
            let endpoint = Endpoint(
                method: .post,
                path: "/book/me/books/\(ticket.bookId)/chapters/\(ticket.chapterNumber)/scenarios",
                httpBody: bodyData
            )
            do {
                let resp: ScenarioResponse = try await apiClient.send(endpoint)
                // Replace local placeholder with server record
                let key = cacheKey(bookId: ticket.bookId, chapterNumber: ticket.chapterNumber)
                if var cached = memCache[key] {
                    var list = cached.scenarios.filter { $0.id != ticket.localScenarioId }
                    list.insert(resp.scenario, at: 0)
                    cached = ScenariosResponse(scenarios: list, community: cached.community)
                    memCache[key] = cached
                }
                ctx.delete(ticket)
                log.info("Scenario outbox sync succeeded: \(ticket.localScenarioId)")
            } catch AppError.offline {
                log.debug("Scenario outbox sync skipped (offline): \(ticket.localScenarioId)")
                break
            } catch {
                ticket.retryCount += 1
                let delay = min(pow(2.0, Double(ticket.retryCount)) * 30, 3_600)
                ticket.nextRetryAt = Date().addingTimeInterval(delay)
                log.warning("Scenario outbox sync failed: \(error). Next retry in \(delay)s")
            }
        }
        try? ctx.save()
    }

    // MARK: - Public: Pending count

    /// Number of scenario submissions still queued in the offline outbox.
    public func pendingUploadCount() -> Int {
        guard let container = modelContainer else { return 0 }
        let ctx = ModelContext(container)
        return (try? ctx.fetchCount(FetchDescriptor<PendingScenarioUpload>())) ?? 0
    }

    // MARK: - Cache invalidation

    public func invalidate(bookId: String, chapterNumber: Int) {
        memCache.removeValue(forKey: cacheKey(bookId: bookId, chapterNumber: chapterNumber))
    }

    public func invalidateAll() {
        memCache.removeAll()
    }

    // MARK: - Private helpers

    private func cacheKey(bookId: String, chapterNumber: Int) -> String {
        "\(bookId)/\(chapterNumber)"
    }

    private func upsertMemory(_ scenario: UserScenario, bookId: String, chapterNumber: Int) {
        let key = cacheKey(bookId: bookId, chapterNumber: chapterNumber)
        var resp = memCache[key] ?? ScenariosResponse(scenarios: [], community: [])
        var list = resp.scenarios
        if let idx = list.firstIndex(where: { $0.id == scenario.id }) {
            list[idx] = scenario
        } else {
            list.insert(scenario, at: 0)
        }
        memCache[key] = ScenariosResponse(scenarios: list, community: resp.community)
    }

    private func mergeWithPendingLocals(
        serverResp: ScenariosResponse,
        bookId: String,
        chapterNumber: Int
    ) -> ScenariosResponse {
        let key = cacheKey(bookId: bookId, chapterNumber: chapterNumber)
        let localPending = (memCache[key]?.scenarios ?? []).filter { $0.id.hasPrefix("local-") }
        let serverIds = Set(serverResp.scenarios.map(\.id))
        let stillPending = localPending.filter { !serverIds.contains($0.id) }
        let merged = stillPending + serverResp.scenarios
        return ScenariosResponse(scenarios: merged, community: serverResp.community)
    }

    private func makeLocalScenario(
        bookId: String,
        chapterNumber: Int,
        body: ScenarioPostBody,
        scope: ScenarioScope
    ) -> UserScenario {
        UserScenario(
            id: "local-\(UUID().uuidString)",
            bookId: bookId,
            chapterNumber: chapterNumber,
            title: body.title,
            scenario: body.scenario,
            whatToDo: body.whatToDo,
            whyItMatters: body.whyItMatters,
            scope: scope,
            status: .pending,
            pointsAwarded: nil,
            createdAt: Date()
        )
    }

    private func enqueueUpload(local: UserScenario, endpoint: Endpoint) {
        guard let container = modelContainer,
              let body = endpoint.httpBody,
              let json = String(data: body, encoding: .utf8) else { return }
        let ticket = PendingScenarioUpload(
            localScenarioId: local.id,
            bookId: local.bookId,
            chapterNumber: local.chapterNumber,
            requestJSON: json
        )
        let ctx = ModelContext(container)
        ctx.insert(ticket)
        do {
            try ctx.save()
            log.info("Queued offline scenario submission: \(local.id)")
        } catch {
            log.warning("Failed to persist scenario outbox ticket: \(error)")
        }
    }
}
