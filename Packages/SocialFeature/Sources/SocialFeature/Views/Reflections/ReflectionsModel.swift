import Foundation
import Observation
import CoreKit

// MARK: - Display item

/// A unified representation for the reflections list — wraps both locally-queued
/// items (not yet on the server) and server-fetched items (full history).
public enum ReflectionDisplayItem: Sendable, Identifiable {
    case pending(PendingReflectionItem)
    case synced(ChapterReflection)

    public var id: String {
        switch self {
        case .pending(let item): "pending-\(item.localId)"
        case .synced(let item): "synced-\(item.reflectionId)"
        }
    }

    public var text: String {
        switch self {
        case .pending(let item): item.text
        case .synced(let item): item.text
        }
    }

    public var createdAt: Date {
        switch self {
        case .pending(let item): item.createdAt
        case .synced(let item): item.createdAt
        }
    }

    public var feedbackText: String? {
        switch self {
        case .pending(let item): item.feedbackText
        case .synced(let item): item.feedbackText
        }
    }

    /// `true` when the reflection has not yet been uploaded to the server.
    public var isLocalPending: Bool {
        if case .pending(let item) = self { return item.syncState == .pending }
        return false
    }

    /// `true` when the AI feedback has been explicitly requested but not yet received.
    public var isFeedbackLoading: Bool {
        if case .pending(let item) = self { return item.feedbackState == .pending }
        return false
    }

    /// `true` when feedback has been received (from the server or local cache).
    public var hasFeedback: Bool { feedbackText != nil }

    /// The localId for pending items, used to queue feedback.
    var localId: String? {
        if case .pending(let item) = self { return item.localId }
        return nil
    }

    /// The server reflection ID, used to request feedback.
    var serverReflectionId: String? {
        switch self {
        case .pending(let item): item.serverReflectionId
        case .synced(let item): item.reflectionId
        }
    }
}

// MARK: - ReflectionsModel

/// Observable model for the chapter reflections screen.
///
/// Orchestrates: fetching history, composing new reflections, requesting AI
/// feedback, and syncing the offline outbox on load.
@Observable
@MainActor
public final class ReflectionsModel {

    public enum LoadPhase: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - Public state

    public private(set) var loadPhase: LoadPhase = .idle
    /// Merged + sorted reflection list (most-recent first). Pending items at top.
    public private(set) var items: [ReflectionDisplayItem] = []

    // Compose state
    public var draftText: String = ""
    public var isSubmitting: Bool = false
    public var submitError: String?

    // Feedback state — IDs currently waiting for AI feedback from the server.
    public private(set) var fetchingFeedbackForIds: Set<String> = []
    public private(set) var feedbackError: String?

    // MARK: - Config

    public let bookId: String
    public let chapterN: Int

    // MARK: - Dependencies

    private let repository: any SocialRepository

    // MARK: - Init

    public init(repository: any SocialRepository, bookId: String, chapterN: Int) {
        self.repository = repository
        self.bookId = bookId
        self.chapterN = chapterN
    }

    // MARK: - Load

    /// Fetches/syncs reflections. Safe to call on appear and on pull-to-refresh.
    public func load() async {
        loadPhase = .loading

        do {
            // 1. Flush the offline outbox first (no-op if nothing pending).
            _ = try await repository.syncPendingReflections(bookId: bookId, chapterN: chapterN)

            // 2. Fetch server history.
            let serverItems = try await repository.getReflections(bookId: bookId, chapterN: chapterN)
            // 3. Fetch still-pending items (those that couldn't be synced).
            let stillPending = await repository.getPendingReflections(bookId: bookId, chapterN: chapterN)
            rebuild(server: serverItems, pending: stillPending)
            loadPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            // If offline, show whatever we have in the outbox + an error.
            let pending = await repository.getPendingReflections(bookId: bookId, chapterN: chapterN)
            rebuild(server: [], pending: pending)
            if items.isEmpty {
                loadPhase = .error(AppError.localizedDescription(error))
            } else {
                loadPhase = .loaded  // Show pending items even when offline
            }
        }

    }

    // MARK: - Compose

    /// Submits the current `draftText` as a new reflection.
    public func submitReflection() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        do {
            let item = try await repository.postReflection(
                bookId: bookId,
                chapterN: chapterN,
                text: text
            )
            draftText = ""
            items.insert(.pending(item), at: 0)
        } catch is CancellationError {
            return
        } catch {
            submitError = AppError.localizedDescription(error)
        }
    }

    // MARK: - AI feedback

    /// Requests AI feedback for a reflection.
    ///
    /// If the reflection is still pending (not yet synced), marks it in the outbox
    /// so feedback is fetched automatically once connectivity returns.
    /// If it's synced, fetches feedback immediately.
    public func requestFeedback(for item: ReflectionDisplayItem) async {
        feedbackError = nil
        fetchingFeedbackForIds.insert(item.id)
        defer { fetchingFeedbackForIds.remove(item.id) }

        if let serverId = item.serverReflectionId {
            // Synced (or pending item that got its serverReflectionId): fetch now.
            do {
                let text = try await repository.requestFeedback(
                    bookId: bookId,
                    chapterN: chapterN,
                    serverReflectionId: serverId
                )
                applyFeedback(text, to: item)
            } catch is CancellationError {
                return
            } catch {
                feedbackError = AppError.localizedDescription(error)
            }
        } else if let localId = item.localId {
            // Pure offline item: queue feedback for when it syncs.
            do {
                _ = try await repository.queueFeedbackForPending(localId: localId)
                updatePendingFeedbackState(localId: localId)
            } catch is CancellationError {
                return
            } catch {
                feedbackError = AppError.localizedDescription(error)
            }
        }
    }

    // MARK: - Private helpers

    private func rebuild(server: [ChapterReflection], pending: [PendingReflectionItem]) {
        // Exclude pending items that have already been synced to the server
        // (the server response is authoritative for those).
        let syncedIds = Set(server.map { $0.reflectionId })
        let filteredPending = pending.filter { item in
            guard let serverId = item.serverReflectionId else { return true }
            return !syncedIds.contains(serverId)
        }

        let pendingDisplay = filteredPending.map { ReflectionDisplayItem.pending($0) }
        let serverDisplay = server.map { ReflectionDisplayItem.synced($0) }

        // Sort each group by date descending, then merge (pending at top).
        let sortedPending = pendingDisplay.sorted { $0.createdAt > $1.createdAt }
        let sortedServer  = serverDisplay.sorted { $0.createdAt > $1.createdAt }
        items = sortedPending + sortedServer
    }

    private func applyFeedback(_ text: String, to displayItem: ReflectionDisplayItem) {
        guard let idx = items.firstIndex(where: { $0.id == displayItem.id }) else { return }
        switch items[idx] {
        case .pending(var pending):
            pending.feedbackState = .received
            pending.feedbackText = text
            items[idx] = .pending(pending)
        case .synced(let reflection):
            let updated = ChapterReflection(
                reflectionId: reflection.reflectionId,
                bookId: reflection.bookId,
                chapterN: reflection.chapterN,
                text: reflection.text,
                createdAt: reflection.createdAt,
                feedbackText: text
            )
            items[idx] = .synced(updated)
        }
    }

    private func updatePendingFeedbackState(localId: String) {
        guard let idx = items.firstIndex(where: {
            if case .pending(let item) = $0 { return item.localId == localId }
            return false
        }) else { return }
        if case .pending(var item) = items[idx] {
            item.feedbackState = .pending
            items[idx] = .pending(item)
        }
    }
}

// MARK: - AppError convenience

private extension AppError {
    static func localizedDescription(_ error: any Error) -> String {
        if let appError = error as? AppError {
            return appError.errorDescription ?? appError.code
        }
        return error.localizedDescription
    }
}
