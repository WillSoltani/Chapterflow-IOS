import Foundation
import Models

// MARK: - Server model

/// A reflection the user wrote for a specific chapter, as returned by the server.
///
/// Maps to `GET /book/me/reflections/{bookId}/{n}` and the success shape of
/// `POST /book/me/reflections/{bookId}/{n}`.
public struct ChapterReflection: Codable, Sendable, Identifiable, Equatable {
    public let reflectionId: String
    public let bookId: String
    public let chapterN: Int
    public let text: String
    public let createdAt: Date
    /// AI-generated feedback, present once the user has requested it and the server
    /// has generated it. `nil` means feedback has not been requested or hasn't
    /// arrived yet.
    public let feedbackText: String?

    public var id: String { reflectionId }

    public init(
        reflectionId: String,
        bookId: String,
        chapterN: Int,
        text: String,
        createdAt: Date,
        feedbackText: String? = nil
    ) {
        self.reflectionId = reflectionId
        self.bookId = bookId
        self.chapterN = chapterN
        self.text = text
        self.createdAt = createdAt
        self.feedbackText = feedbackText
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reflectionId = try c.decode(String.self, forKey: .reflectionId)
        bookId       = try c.decode(String.self, forKey: .bookId)
        chapterN     = try c.decode(Int.self,    forKey: .chapterN)
        text         = try c.decode(String.self, forKey: .text)
        createdAt    = try c.decode(Date.self,   forKey: .createdAt)
        feedbackText = try c.decodeIfPresent(String.self, forKey: .feedbackText)
    }

    private enum CodingKeys: String, CodingKey {
        case reflectionId, bookId, chapterN, text, createdAt, feedbackText
    }
}

// MARK: - API response envelopes

/// Success envelope for `GET /book/me/reflections/{bookId}/{n}`.
///
/// Decodes the `reflections` array lossily — one malformed item never breaks
/// the rest of the history.
public struct ReflectionsResponse: Codable, Sendable {
    public let reflections: [ChapterReflection]

    private enum CodingKeys: String, CodingKey { case reflections }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reflections = try c.decodeLossy(ChapterReflection.self, forKey: .reflections)
    }
}

/// Success envelope for `POST /book/me/reflections/{bookId}/{n}`.
public struct PostReflectionResponse: Codable, Sendable {
    public let reflection: ChapterReflection
}

/// Success envelope for `POST /book/me/reflections/{bookId}/{n}/feedback`.
public struct ReflectionFeedbackResponse: Codable, Sendable {
    public let feedbackText: String
}

// MARK: - Pending (offline-queued) reflection

/// A reflection that the user wrote while offline (or whose upload has not yet succeeded).
///
/// Lives in the local ``ReflectionOutbox`` until it is successfully POSTed to the server.
/// Once synced, `syncState == .synced` and `serverReflectionId` is populated.
/// If the user requested AI feedback before the reflection was synced, `feedbackState`
/// is set to `.pending` so the outbox can request it automatically after a successful sync.
public struct PendingReflectionItem: Codable, Sendable, Identifiable, Equatable {
    public let localId: String
    public let bookId: String
    public let chapterN: Int
    public let text: String
    public let createdAt: Date
    public var syncState: SyncState
    public var serverReflectionId: String?
    public var feedbackState: FeedbackState
    public var feedbackText: String?

    public var id: String { localId }

    public enum SyncState: String, Codable, Sendable, Equatable {
        case pending
        case synced
    }

    public enum FeedbackState: String, Codable, Sendable, Equatable {
        /// User has not asked for AI feedback.
        case none
        /// User asked for feedback; will be fetched once the reflection is synced.
        case pending
        /// AI feedback was received and is stored in `feedbackText`.
        case received
    }

    public init(
        localId: String = UUID().uuidString,
        bookId: String,
        chapterN: Int,
        text: String,
        createdAt: Date = Date(),
        syncState: SyncState = .pending,
        serverReflectionId: String? = nil,
        feedbackState: FeedbackState = .none,
        feedbackText: String? = nil
    ) {
        self.localId = localId
        self.bookId = bookId
        self.chapterN = chapterN
        self.text = text
        self.createdAt = createdAt
        self.syncState = syncState
        self.serverReflectionId = serverReflectionId
        self.feedbackState = feedbackState
        self.feedbackText = feedbackText
    }
}
