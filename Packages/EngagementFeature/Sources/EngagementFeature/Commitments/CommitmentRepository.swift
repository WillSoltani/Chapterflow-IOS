import Foundation
import CoreKit
import Models
import Networking
import Persistence
import SwiftData
import UserNotifications
import OSLog

private let log = Logger(subsystem: "com.chapterflow.engagement", category: "commitments")

// MARK: - CommitmentRepository

/// Manages if-then commitments: CRUD against the API with offline queuing via the
/// outbox and local-notification scheduling for follow-up reminders.
///
/// Endpoints:
/// - `GET  /book/me/commitments`
/// - `POST /book/me/commitments`
/// - `GET  /book/me/commitments/{id}`
/// - `PATCH /book/me/commitments/{id}`
public actor CommitmentRepository {

    // MARK: Dependencies

    private let apiClient: any APIClientProtocol
    private let modelContainer: ModelContainer?

    // MARK: In-memory cache

    private var memCommitments: [Commitment]?

    // MARK: Init

    public init(apiClient: some APIClientProtocol, modelContainer: ModelContainer? = nil) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
    }

    // MARK: - Fetch all commitments

    /// Fetches the user's commitments from the server or falls back to the last
    /// in-memory state when offline. Merges any pending local creates.
    public func fetchCommitments(forceRefresh: Bool = false) async throws -> [Commitment] {
        if !forceRefresh, let cached = memCommitments {
            return cached
        }
        do {
            let resp: CommitmentsResponse = try await apiClient.send(Endpoints.getCommitments())
            let merged = mergeWithPendingLocals(serverList: resp.commitments)
            memCommitments = merged
            return merged
        } catch AppError.offline {
            if let cached = memCommitments { return cached }
            throw AppError.offline
        }
    }

    // MARK: - Create

    /// Creates a new commitment and schedules a local follow-up notification.
    /// Queues the write to the offline outbox if the network is unavailable.
    public func createCommitment(
        bookId: String,
        chapterId: String,
        ifStatement: String,
        thenStatement: String,
        followUpDays: Int
    ) async throws -> Commitment {
        let endpoint = try Endpoints.createCommitment(
            bookId: bookId,
            chapterId: chapterId,
            ifStatement: ifStatement,
            thenStatement: thenStatement,
            followUpDays: followUpDays
        )
        do {
            let resp: CommitmentResponse = try await apiClient.send(endpoint)
            let commitment = resp.commitment
            upsertMemory(commitment)
            scheduleNotification(for: commitment)
            return commitment
        } catch AppError.offline {
            let local = makeLocalCommitment(
                bookId: bookId,
                chapterId: chapterId,
                ifStatement: ifStatement,
                thenStatement: thenStatement,
                followUpDays: followUpDays
            )
            upsertMemory(local)
            scheduleNotification(for: local)
            enqueueCreate(local: local, endpoint: endpoint)
            return local
        }
    }

    // MARK: - Reflect (PATCH)

    /// Submits a reflection and outcome for the commitment at follow-up time.
    /// Queues the write offline if connectivity is unavailable.
    public func submitReflection(
        commitmentId: String,
        reflection: String,
        outcome: CommitmentOutcome
    ) async throws -> Commitment {
        let endpoint = try Endpoints.updateCommitment(
            id: commitmentId,
            reflection: reflection,
            outcomeRawValue: outcome.rawValue
        )
        do {
            let resp: CommitmentResponse = try await apiClient.send(endpoint)
            let updated = resp.commitment
            upsertMemory(updated)
            cancelNotification(id: commitmentId)
            return updated
        } catch AppError.offline {
            let updated = optimisticallyApplyReflection(
                commitmentId: commitmentId,
                reflection: reflection,
                outcome: outcome
            )
            enqueueUpdate(commitmentId: commitmentId, endpoint: endpoint)
            return updated
        }
    }

    // MARK: - Fetch single (with server refresh)

    public func fetchCommitment(id: String) async throws -> Commitment {
        let resp: CommitmentResponse = try await apiClient.send(Endpoints.getCommitment(id: id))
        upsertMemory(resp.commitment)
        return resp.commitment
    }

    // MARK: - Accessors

    public var commitments: [Commitment]? { memCommitments }

    public var activeCommitments: [Commitment] {
        (memCommitments ?? []).filter { $0.status == .active }
    }

    public func invalidate() {
        memCommitments = nil
    }

    // MARK: - Local notification scheduling
    // Notifications are iOS/macOS app-bundle features and crash if called from a
    // test runner process that has no app bundle. Guard on canImport(UIKit) so the
    // actor still compiles and tests pass on macOS without a bundle.

    private func scheduleNotification(for commitment: Commitment) {
        #if canImport(UIKit)
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Time for your commitment check-in"
        content.body = "If \(commitment.ifStatement) — how did it go?"
        content.sound = .default
        content.userInfo = ["commitmentId": commitment.id, "type": "commitment_followup"]

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: commitment.followUpDate
        )
        components.hour = components.hour ?? 9
        components.minute = components.minute ?? 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: notificationId(for: commitment.id),
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error {
                log.warning("Failed to schedule commitment notification: \(error)")
            }
        }
        #endif
    }

    private func cancelNotification(id: String) {
        #if canImport(UIKit)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId(for: id)])
        #endif
    }

    private func notificationId(for commitmentId: String) -> String {
        "commitment_followup_\(commitmentId)"
    }

    // MARK: - Memory helpers

    private func upsertMemory(_ commitment: Commitment) {
        var list = memCommitments ?? []
        if let idx = list.firstIndex(where: { $0.id == commitment.id }) {
            list[idx] = commitment
        } else {
            list.insert(commitment, at: 0)
        }
        memCommitments = list
    }

    private func mergeWithPendingLocals(serverList: [Commitment]) -> [Commitment] {
        // Pending local IDs start with "local-" — keep them at the front until
        // the outbox sync delivers them and they appear in the server list.
        let localOnly = (memCommitments ?? []).filter { $0.id.hasPrefix("local-") }
        let serverIds = Set(serverList.map(\.id))
        let stillPending = localOnly.filter { !serverIds.contains($0.id) }
        return stillPending + serverList
    }

    private func optimisticallyApplyReflection(
        commitmentId: String,
        reflection: String,
        outcome: CommitmentOutcome
    ) -> Commitment {
        guard let existing = memCommitments?.first(where: { $0.id == commitmentId }) else {
            // Synthesise a minimal placeholder so the caller has something to show.
            let placeholder = Commitment(
                id: commitmentId,
                bookId: "",
                chapterId: "",
                ifStatement: "",
                thenStatement: "",
                followUpDate: Date(),
                status: .done,
                outcome: outcome,
                reflection: reflection,
                createdAt: Date()
            )
            upsertMemory(placeholder)
            return placeholder
        }
        let updated = Commitment(
            id: existing.id,
            bookId: existing.bookId,
            chapterId: existing.chapterId,
            ifStatement: existing.ifStatement,
            thenStatement: existing.thenStatement,
            followUpDate: existing.followUpDate,
            status: .done,
            outcome: outcome,
            reflection: reflection,
            createdAt: existing.createdAt
        )
        upsertMemory(updated)
        return updated
    }

    // MARK: - Offline outbox

    private func enqueueCreate(local: Commitment, endpoint: Endpoint) {
        guard let container = modelContainer,
              let body = endpoint.httpBody,
              let json = String(data: body, encoding: .utf8) else { return }
        let ticket = PendingCommitmentUpload(
            localCommitmentId: local.id,
            operation: "create",
            requestJSON: json
        )
        let ctx = ModelContext(container)
        ctx.insert(ticket)
        do {
            try ctx.save()
            log.info("Queued offline commitment create: \(local.id)")
        } catch {
            log.warning("Failed to persist commitment outbox ticket: \(error)")
        }
    }

    private func enqueueUpdate(commitmentId: String, endpoint: Endpoint) {
        guard let container = modelContainer,
              let body = endpoint.httpBody,
              let json = String(data: body, encoding: .utf8) else { return }
        let ticket = PendingCommitmentUpload(
            localCommitmentId: commitmentId,
            operation: "update",
            serverCommitmentId: commitmentId,
            requestJSON: json
        )
        let ctx = ModelContext(container)
        ctx.insert(ticket)
        do {
            try ctx.save()
            log.info("Queued offline commitment update: \(commitmentId)")
        } catch {
            log.warning("Failed to persist commitment update outbox ticket: \(error)")
        }
    }

    // MARK: - Local placeholder builder

    private func makeLocalCommitment(
        bookId: String,
        chapterId: String,
        ifStatement: String,
        thenStatement: String,
        followUpDays: Int
    ) -> Commitment {
        let followUp = Calendar.current.date(
            byAdding: .day,
            value: followUpDays,
            to: Date()
        ) ?? Date()
        return Commitment(
            id: "local-\(UUID().uuidString)",
            bookId: bookId,
            chapterId: chapterId,
            ifStatement: ifStatement,
            thenStatement: thenStatement,
            followUpDate: followUp,
            status: .active,
            outcome: nil,
            reflection: nil,
            createdAt: Date()
        )
    }
}
