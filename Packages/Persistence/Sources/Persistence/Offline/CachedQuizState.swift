import Foundation
import SwiftData
import Models

/// Status of a cached quiz session and its local draft.
public enum QuizCacheStatus: String, Sendable, CaseIterable {
    /// Questions fetched with no locally saved answers.
    case ready
    /// Answers are saved locally and require an explicit online submit.
    case draftPendingOnline
    /// Legacy readable value. New code never creates automatic grading work.
    case pendingGrading
}

/// The versioned payload stored inside ``CachedQuizState/dataJSON``.
///
/// It intentionally contains only the server-projected questions and the user's
/// selected choice IDs. It never contains answer keys, correctness, or grading.
public struct CachedQuizDocument: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let session: QuizClientSession
    public let selectedAnswers: [String: String]

    public init(
        version: Int = Self.currentVersion,
        session: QuizClientSession,
        selectedAnswers: [String: String]
    ) throws {
        guard version == Self.currentVersion else {
            throw CachedQuizDocumentError.unsupportedVersion(version)
        }
        try Self.validate(selectedAnswers, for: session)
        self.version = version
        self.session = session
        self.selectedAnswers = selectedAnswers
    }

    private enum CodingKeys: String, CodingKey {
        case version, session, selectedAnswers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let session = try container.decode(QuizClientSession.self, forKey: .session)
        let answers = try container.decodeIfPresent(
            [String: String].self,
            forKey: .selectedAnswers
        ) ?? [:]
        try self.init(version: version, session: session, selectedAnswers: answers)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(session, forKey: .session)
        try container.encode(selectedAnswers, forKey: .selectedAnswers)
    }

    /// Returns answers only when both attempt identity and assigned questions/choices match.
    public func answers(matching currentSession: QuizClientSession) -> [String: String] {
        guard let cachedAttempt = session.attemptNumber,
              cachedAttempt > 0,
              currentSession.attemptNumber == cachedAttempt,
              Self.questionSignature(session) == Self.questionSignature(currentSession) else {
            return [:]
        }
        return selectedAnswers
    }

    private static func validate(
        _ selectedAnswers: [String: String],
        for session: QuizClientSession
    ) throws {
        if !selectedAnswers.isEmpty {
            guard let attemptNumber = session.attemptNumber, attemptNumber > 0 else {
                throw CachedQuizDocumentError.missingAttemptNumber
            }
        }

        var choicesByQuestion: [String: Set<String>] = [:]
        for question in session.questions {
            guard choicesByQuestion[question.questionId] == nil else {
                throw CachedQuizDocumentError.duplicateQuestion(question.questionId)
            }
            choicesByQuestion[question.questionId] = Set(question.choices.map(\.choiceId))
        }
        for (questionID, choiceID) in selectedAnswers {
            guard choicesByQuestion[questionID]?.contains(choiceID) == true else {
                throw CachedQuizDocumentError.invalidSelection(questionID: questionID)
            }
        }
    }

    private static func questionSignature(
        _ session: QuizClientSession
    ) -> [String: Set<String>] {
        Dictionary(
            session.questions.map { ($0.questionId, Set($0.choices.map(\.choiceId))) },
            uniquingKeysWith: { current, _ in current }
        )
    }
}

public enum CachedQuizDocumentError: Error, Sendable, Equatable {
    case unsupportedVersion(Int)
    case missingAttemptNumber
    case duplicateQuestion(String)
    case invalidSelection(questionID: String)
    case invalidEncoding
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
    /// Legacy cache compatibility only. Current submit uses `attemptNumber` from `dataJSON`.
    public var sessionId: String?
    /// JSON-encoded ``CachedQuizDocument``. Legacy rows may contain a bare session.
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
    public static func makeRowId(userId: String, bookId: String, chapterNumber: Int) -> String {
        "\(userId):\(bookId):\(chapterNumber)"
    }

    public static func from(
        _ domain: QuizClientSession,
        userId: String,
        bookId: String,
        chapterNumber: Int,
        selectedAnswers: [String: String] = [:],
        status: QuizCacheStatus = .ready
    ) throws -> CachedQuizState {
        let document = try CachedQuizDocument(
            session: domain,
            selectedAnswers: selectedAnswers
        )
        let data = try JSONEncoder().encode(document)
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
        try toDocument().session
    }

    /// Decodes the current document first, then the legacy bare-session shape.
    public func toDocument() throws -> CachedQuizDocument {
        let data = Data(dataJSON.utf8)
        if let document = try? JSONDecoder.chapterFlow.decode(
            CachedQuizDocument.self,
            from: data
        ) {
            return document
        }
        let legacySession = try JSONDecoder.chapterFlow.decode(
            QuizClientSession.self,
            from: data
        )
        return try CachedQuizDocument(session: legacySession, selectedAnswers: [:])
    }

    public func restoredAnswers(matching session: QuizClientSession) throws -> [String: String] {
        try toDocument().answers(matching: session)
    }

    /// The typed status value. Defaults to `.ready` for any unrecognised raw value.
    public var status: QuizCacheStatus {
        QuizCacheStatus(rawValue: statusRaw) ?? .ready
    }
}
