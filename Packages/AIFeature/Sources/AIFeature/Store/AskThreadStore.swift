import Foundation
import SwiftData
import Persistence
import OSLog

private let log = Logger(subsystem: "com.chapterflow.ai", category: "AskThreadStore")

/// Reads and writes Q&A threads for one user+book pair from the SwiftData store.
///
/// All methods are synchronous and must be called on the @MainActor (the main
/// context is not Sendable). Pass the main-context from ``PersistenceController``.
@MainActor
public struct AskThreadStore {

    // MARK: - Load

    /// Loads all persisted messages for a given book/user, sorted oldest-first.
    /// Returns an empty array if no thread exists yet.
    public static func loadMessages(
        bookId: String,
        userId: String,
        context: ModelContext
    ) -> [StoredAskMessage] {
        let threadId = CachedAskThread.makeThreadId(userId: userId, bookId: bookId)
        var descriptor = FetchDescriptor<CachedAskThread>(
            predicate: #Predicate { $0.threadId == threadId }
        )
        descriptor.fetchLimit = 1
        guard let thread = try? context.fetch(descriptor).first else { return [] }
        let data = Data(thread.messagesJSON.utf8)
        // Use the standard decoder — StoredAskMessage is local data, not from the server.
        let messages = (try? JSONDecoder().decode([StoredAskMessage].self, from: data)) ?? []
        return messages
    }

    /// Loads all threads for a given user, sorted by most-recently-updated first.
    public static func allThreads(
        userId: String,
        context: ModelContext
    ) -> [CachedAskThread] {
        var descriptor = FetchDescriptor<CachedAskThread>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.lastUpdatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Upsert

    /// Saves (or replaces) the full message list for a book/user thread.
    public static func upsertThread(
        bookId: String,
        userId: String,
        bookTitle: String?,
        messages: [StoredAskMessage],
        context: ModelContext
    ) {
        let threadId = CachedAskThread.makeThreadId(userId: userId, bookId: bookId)
        var descriptor = FetchDescriptor<CachedAskThread>(
            predicate: #Predicate { $0.threadId == threadId }
        )
        descriptor.fetchLimit = 1

        let json: String
        if let data = try? JSONEncoder().encode(messages),
           let str = String(bytes: data, encoding: .utf8) {
            json = str
        } else {
            json = "[]"
        }

        if let existing = (try? context.fetch(descriptor))?.first {
            existing.messagesJSON = json
            existing.messageCount = messages.count
            existing.lastUpdatedAt = Date()
            if let title = bookTitle { existing.bookTitle = title }
        } else {
            let thread = CachedAskThread(
                threadId: threadId,
                userId: userId,
                bookId: bookId,
                bookTitle: bookTitle,
                messagesJSON: json,
                messageCount: messages.count
            )
            context.insert(thread)
        }

        do {
            try context.save()
        } catch {
            log.error("AskThreadStore: save failed — \(error.localizedDescription)")
        }
    }

    /// Updates the `isPinned` flag for a single message inside a thread.
    public static func updatePinState(
        messageId: String,
        isPinned: Bool,
        bookId: String,
        userId: String,
        context: ModelContext
    ) {
        var messages = loadMessages(bookId: bookId, userId: userId, context: context)
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].isPinned = isPinned
        // bookTitle not needed for a pin update — pass nil to preserve existing value.
        upsertThread(bookId: bookId, userId: userId, bookTitle: nil, messages: messages, context: context)
    }
}
