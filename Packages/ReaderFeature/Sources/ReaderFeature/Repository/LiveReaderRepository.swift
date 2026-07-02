import Foundation
import Models
import Networking
import Persistence
import os

// MARK: - Live implementation

/// Production `ReaderRepository` backed by `APIClient` and `KeyValueStore`.
/// `@unchecked Sendable`: `KeyValueStore` wraps `UserDefaults` which is
/// documented thread-safe; `JSONEncoder`/`JSONDecoder` use value semantics.
public struct LiveReaderRepository: ReaderRepository, @unchecked Sendable {
    private let client: any APIClientProtocol
    private let store: KeyValueStore
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "ReaderRepository")

    public init(client: any APIClientProtocol, store: KeyValueStore = KeyValueStore()) {
        self.client = client
        self.store = store
    }

    // MARK: - Chapter loading

    public func getChapter(bookId: String, n: Int, mode: String?) async throws -> ChapterResponse {
        let endpoint = Endpoints.getChapter(bookId: bookId, n: n, mode: mode)
        return try await client.send(endpoint)
    }

    // MARK: - Cursor patch

    public func patchBookCursor(bookId: String, chapterId: String) async throws {
        let endpoint = try Endpoints.patchBookCursor(bookId: bookId, chapterId: chapterId)
        // Decode the state response; result is not needed by the caller.
        let _: BookStateResponse = try await client.send(endpoint)
    }

    // MARK: - Session heartbeat (fire-and-forget)

    public func postReadingHeartbeat(bookId: String, chapterId: String) async {
        do {
            let endpoint = try Endpoints.postReadingSessionEvent(
                event: "heartbeat",
                bookId: bookId,
                chapterId: chapterId,
                sessionId: nil
            )
            // P2.7 will add a proper session-lifecycle response model.
            // For now accept any decodable response without using the result.
            let _: ReadingSessionResponse = try await client.send(endpoint)
        } catch {
            logger.debug("Reading heartbeat failed (suppressed): \(error.localizedDescription)")
        }
    }

    // MARK: - Position persistence

    public func saveScrollPosition(bookId: String, chapterNumber: Int, blockIndex: Int) {
        let key = positionKey(bookId: bookId, chapterNumber: chapterNumber)
        try? store.set(blockIndex, forKey: key)
    }

    public func loadScrollPosition(bookId: String, chapterNumber: Int) -> Int? {
        let key = positionKey(bookId: bookId, chapterNumber: chapterNumber)
        return store.value(Int.self, forKey: key)
    }

    // MARK: - Private

    private func positionKey(bookId: String, chapterNumber: Int) -> String {
        "reader.position.v1.\(bookId).\(chapterNumber)"
    }
}

// MARK: - Minimal response types

/// Minimal response from `POST /book/me/reading-sessions`.
/// Full session lifecycle (sessionId, start/end) is implemented in P2.7.
struct ReadingSessionResponse: Decodable, Sendable {
    let sessionId: String?
}
