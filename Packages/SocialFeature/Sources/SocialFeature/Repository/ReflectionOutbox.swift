import Foundation
import CoreKit
import os

/// Value-free failures raised while opening required account-owned social storage.
///
/// No case carries a namespace, path, or underlying error so diagnostics cannot
/// disclose account-derived storage identifiers.
public enum SocialPrivateStorageFailure: Error, Equatable, Sendable {
    case invalidStorageNamespace
    case requiredAccountDirectory
    case unreadableReflectionOutbox
}

/// A file-backed, actor-isolated outbox for offline-queued chapter reflections.
///
/// Write once, sync-when-ready: every `PendingReflectionItem` added here is
/// persisted to disk immediately so it survives app restarts. The outbox is
/// internal to `SocialFeature`; consumers interact through `SocialRepository`.
actor ReflectionOutbox {

    private var items: [PendingReflectionItem] = []
    private let fileURL: URL
    private let workPermit: SessionWorkPermit
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "ReflectionOutbox")

    init(
        storageNamespace: String,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) throws {
        let applicationSupport: URL
        do {
            applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw SocialPrivateStorageFailure.requiredAccountDirectory
        }

        let storage = try Self.loadStorage(
            storageNamespace: storageNamespace,
            applicationSupportDirectory: applicationSupport
        )
        fileURL = storage.fileURL
        items = storage.items
        self.workPermit = workPermit
    }

    /// Deterministic filesystem seam used by package tests.
    init(
        storageNamespace: String,
        applicationSupportDirectory: URL,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) throws {
        let storage = try Self.loadStorage(
            storageNamespace: storageNamespace,
            applicationSupportDirectory: applicationSupportDirectory
        )
        fileURL = storage.fileURL
        items = storage.items
        self.workPermit = workPermit
    }

    private static func loadStorage(
        storageNamespace: String,
        applicationSupportDirectory: URL
    ) throws -> (fileURL: URL, items: [PendingReflectionItem]) {
        guard isValidAccountStorageNamespace(storageNamespace) else {
            throw SocialPrivateStorageFailure.invalidStorageNamespace
        }
        let accountDirectory = applicationSupportDirectory
            .appending(path: "com.chapterflow", directoryHint: .isDirectory)
            .appending(path: "accounts", directoryHint: .isDirectory)
            .appending(path: storageNamespace, directoryHint: .isDirectory)

        do {
            try FileManager.default.createDirectory(
                at: accountDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw SocialPrivateStorageFailure.requiredAccountDirectory
        }

        let fileURL = accountDirectory.appending(path: "pending_reflections.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (fileURL, [])
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let items = try JSONDecoder.chapterFlow.decode([PendingReflectionItem].self, from: data)
            return (fileURL, items)
        } catch {
            throw SocialPrivateStorageFailure.unreadableReflectionOutbox
        }
    }

    private static func isValidAccountStorageNamespace(_ value: String) -> Bool {
        let prefix = "account-v1-"
        guard value.hasPrefix(prefix) else { return false }
        let digest = value.dropFirst(prefix.count)
        guard digest.count == 64 else { return false }
        return digest.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character)
        }
    }

    /// Test-only initializer with an explicit file URL so tests don't touch the real app storage.
    init(fileURL: URL, workPermit: SessionWorkPermit = SessionWorkPermit()) {
        self.fileURL = fileURL
        self.workPermit = workPermit
        // No existing items in a fresh temp file.
    }

    // MARK: - Query

    func all(bookId: String, chapterN: Int) -> [PendingReflectionItem] {
        items.filter { $0.bookId == bookId && $0.chapterN == chapterN }
    }

    // MARK: - Mutations

    func append(_ item: PendingReflectionItem, ticket: UInt64) throws {
        try commit(ticket: ticket) { updated in
            updated.append(item)
        }
    }

    func update(_ item: PendingReflectionItem, ticket: UInt64) throws {
        try commit(ticket: ticket) { updated in
            guard let idx = updated.firstIndex(where: { $0.localId == item.localId }) else { return }
            updated[idx] = item
        }
    }

    func markFeedbackPending(localId: String, ticket: UInt64) throws {
        try commit(ticket: ticket) { updated in
            guard let idx = updated.firstIndex(where: { $0.localId == localId }) else { return }
            updated[idx].feedbackState = .pending
        }
    }

    func markFeedbackReceived(
        localId: String,
        feedbackText: String,
        ticket: UInt64
    ) throws {
        try commit(ticket: ticket) { updated in
            guard let idx = updated.firstIndex(where: { $0.localId == localId }) else { return }
            updated[idx].feedbackState = .received
            updated[idx].feedbackText = feedbackText
        }
    }

    func remove(localId: String, ticket: UInt64) throws {
        try commit(ticket: ticket) { updated in
            updated.removeAll { $0.localId == localId }
        }
    }

    // MARK: - Persistence

    private func commit(
        ticket: UInt64,
        _ operation: (inout [PendingReflectionItem]) -> Void
    ) throws {
        try workPermit.commit(ticket) {
            var updated = items
            operation(&updated)
            try persist(updated)
            items = updated
        }
    }

    private func persist(_ updated: [PendingReflectionItem]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(updated)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.warning("Failed to persist reflection outbox")
            throw error
        }
    }
}
