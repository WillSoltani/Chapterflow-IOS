import Foundation
import SwiftData
import Models

/// Status of a cached offline quiz session.
///
/// A quiz taken offline is stored as `pendingGrading` — the app never grades
/// locally and never stores answer keys. The `quizSubmit` PendingMutation
/// carries the answers to the server when connectivity returns.
public enum QuizCacheStatus: String, Sendable, CaseIterable {
    /// Questions fetched; not yet submitted.
    case ready
    /// Submitted offline; awaiting server grading.
    case pendingGrading
}

/// A cached ``QuizClientSession`` for offline quiz access.
///
/// Contains only the questions and metadata — never the answers or grading keys.
@Model
public final class CachedQuizState {
    /// Composite unique key: "userId:bookId:chapterNumber".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    public var chapterNumber: Int
    /// The server-assigned session ID (nil if the session hasn't been started yet).
    public var sessionId: String?
    /// JSON-encoded QuizClientSession (questions only — no answers/keys).
    public var dataJSON: String
    /// Raw QuizCacheStatus value.
    public var statusRaw: String
    public var cachedAt: Date

    public init(
        rowId: String,
        userId: String,
        bookId: String,
        chapterNumber: Int,
        sessionId: String? = nil,
        dataJSON: String,
        statusRaw: String = QuizCacheStatus.ready.rawValue,
        cachedAt: Date = Date()
    ) {
        self.rowId = rowId
        self.userId = userId
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.sessionId = sessionId
        self.dataJSON = dataJSON
        self.statusRaw = statusRaw
        self.cachedAt = cachedAt
    }
}

// MARK: - Domain mapping

extension CachedQuizState {
    static func makeRowId(userId: String, bookId: String, chapterNumber: Int) -> String {
        "\(userId):\(bookId):\(chapterNumber)"
    }

    public static func from(
        _ domain: QuizClientSession,
        userId: String,
        bookId: String,
        chapterNumber: Int,
        status: QuizCacheStatus = .ready
    ) throws -> CachedQuizState {
        let data = try JSONEncoder().encode(domain)
        return CachedQuizState(
            rowId: makeRowId(userId: userId, bookId: bookId, chapterNumber: chapterNumber),
            userId: userId,
            bookId: bookId,
            chapterNumber: chapterNumber,
            sessionId: domain.sessionId,
            dataJSON: String(bytes: data, encoding: .utf8) ?? "",
            statusRaw: status.rawValue
        )
    }

    public func toDomain() throws -> QuizClientSession {
        try JSONDecoder.chapterFlow.decode(QuizClientSession.self, from: Data(dataJSON.utf8))
    }

    /// The typed status value. Defaults to `.ready` for any unrecognised raw value.
    public var status: QuizCacheStatus {
        QuizCacheStatus(rawValue: statusRaw) ?? .ready
    }
}
