import Foundation

// MARK: - ProgressCursorPayload

/// Payload for ``MutationKind/progressCursor``.
///
/// Carries enough context to replay `PATCH /book/me/books/{bookId}/state`
/// with the cursor fields only — the SyncEngine never writes gating fields.
public struct ProgressCursorPayload: Codable, Sendable {
    public let bookId: String
    public let chapterId: String

    public init(bookId: String, chapterId: String) {
        self.bookId = bookId
        self.chapterId = chapterId
    }
}

// MARK: - QuizSubmitPayload

/// Payload for ``MutationKind/quizSubmit``.
///
/// The `sessionId` is the server-issued ID from `QuizClientSession.sessionId`.
/// It is the idempotency key: the server rejects duplicate submits with the
/// same sessionId and returns the original result (or an "already submitted"
/// error that the SyncEngine treats as success).
///
/// **No answer keys are stored here.** Grading is always server-side.
public struct QuizSubmitPayload: Codable, Sendable {
    public let bookId: String
    public let chapterNumber: Int
    public let sessionId: String
    /// Maps `questionId` → `selectedChoiceId`. Never contains correct answers.
    public let answers: [String: String]

    public init(bookId: String, chapterNumber: Int, sessionId: String, answers: [String: String]) {
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.sessionId = sessionId
        self.answers = answers
    }
}

// MARK: - NotebookWritePayload

/// Payload for ``MutationKind/notebookWrite`` (notes and bookmarks).
public struct NotebookWritePayload: Codable, Sendable {
    /// Non-nil → update the existing entry; nil → create new.
    public let entryId: String?
    public let bookId: String
    public let chapterId: String
    /// `"note"` or `"bookmark"`.
    public let type: String
    public let content: String?
    public let quote: String?
    public let color: String?

    public init(
        entryId: String? = nil,
        bookId: String,
        chapterId: String,
        type: String,
        content: String? = nil,
        quote: String? = nil,
        color: String? = nil
    ) {
        self.entryId = entryId
        self.bookId = bookId
        self.chapterId = chapterId
        self.type = type
        self.content = content
        self.quote = quote
        self.color = color
    }
}

// MARK: - HighlightWritePayload

/// Payload for ``MutationKind/highlightWrite``.
///
/// Highlights are anchored to the *resolved* (variant, tone) content so they
/// survive server-side content changes between when the user highlighted and
/// when the mutation is synced.
public struct HighlightWritePayload: Codable, Sendable {
    /// Non-nil → update existing entry; nil → create new.
    public let entryId: String?
    public let bookId: String
    public let chapterId: String
    public let variantKey: String
    public let toneKey: String
    public let blockIndex: Int
    public let blockType: String
    public let startChar: Int
    public let endChar: Int
    public let snippet: String
    public let color: String

    public init(
        entryId: String? = nil,
        bookId: String,
        chapterId: String,
        variantKey: String,
        toneKey: String,
        blockIndex: Int,
        blockType: String,
        startChar: Int,
        endChar: Int,
        snippet: String,
        color: String
    ) {
        self.entryId = entryId
        self.bookId = bookId
        self.chapterId = chapterId
        self.variantKey = variantKey
        self.toneKey = toneKey
        self.blockIndex = blockIndex
        self.blockType = blockType
        self.startChar = startChar
        self.endChar = endChar
        self.snippet = snippet
        self.color = color
    }
}

// MARK: - ReviewGradePayload

/// Payload for ``MutationKind/reviewGrade``.
public struct ReviewGradePayload: Codable, Sendable {
    public let cardId: String
    /// FSRS rating: 1=Again, 2=Hard, 3=Good, 4=Easy.
    public let rating: Int

    public init(cardId: String, rating: Int) {
        self.cardId = cardId
        self.rating = rating
    }
}

// MARK: - CommitmentPayload

/// Payload for ``MutationKind/commitment``.
///
/// Either creates a new commitment (`commitmentId == nil`) or submits the
/// follow-up reflection/outcome for an existing one (`commitmentId != nil`).
public struct CommitmentPayload: Codable, Sendable {
    /// Non-nil → update path (reflection + outcome); nil → create path.
    public let commitmentId: String?
    public let bookId: String
    public let chapterId: String
    public let ifStatement: String?
    public let thenStatement: String?
    public let followUpDays: Int?
    /// Follow-up reflection text (update path only).
    public let reflection: String?
    /// Outcome raw value (update path only): `"helped"`, `"partly"`, or `"didnt"`.
    public let outcome: String?

    public init(
        commitmentId: String? = nil,
        bookId: String,
        chapterId: String,
        ifStatement: String? = nil,
        thenStatement: String? = nil,
        followUpDays: Int? = nil,
        reflection: String? = nil,
        outcome: String? = nil
    ) {
        self.commitmentId = commitmentId
        self.bookId = bookId
        self.chapterId = chapterId
        self.ifStatement = ifStatement
        self.thenStatement = thenStatement
        self.followUpDays = followUpDays
        self.reflection = reflection
        self.outcome = outcome
    }
}

// MARK: - SavedTogglePayload

/// Payload for ``MutationKind/savedToggle``.
public struct SavedTogglePayload: Codable, Sendable {
    public let bookId: String
    public let saved: Bool

    public init(bookId: String, saved: Bool) {
        self.bookId = bookId
        self.saved = saved
    }
}

// MARK: - ReadingSessionPayload

/// Payload for ``MutationKind/readingSession``.
public struct ReadingSessionPayload: Codable, Sendable {
    /// `"start"`, `"heartbeat"`, or `"end"`.
    public let event: String
    public let bookId: String
    public let chapterId: String
    public let sessionId: String?

    public init(event: String, bookId: String, chapterId: String, sessionId: String?) {
        self.event = event
        self.bookId = bookId
        self.chapterId = chapterId
        self.sessionId = sessionId
    }
}
