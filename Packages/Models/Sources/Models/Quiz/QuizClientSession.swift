/// A quiz client session returned by `GET /book/books/{bookId}/chapters/{n}/quiz`.
///
/// Contains questions for the UI; grading is **always server-side**.
/// Submit selected choice IDs with the exact server-issued `attemptNumber` —
/// never grade locally and never infer a missing attempt identity.
public struct QuizClientSession: Codable, Sendable, Equatable {
    /// Legacy cache compatibility only. Current production submit never reads this value.
    public let sessionId: String?
    /// The server-issued identity of the currently represented attempt.
    public let attemptNumber: Int?
    /// The next attempt reported by the server, when one exists.
    public let nextAttemptNumber: Int?
    /// Server-owned lifecycle state. Unknown values remain opaque and fail closed.
    public let status: QuizSessionStatus?
    public let questions: [QuizQuestion]
    public let passingScorePercent: Int?
    public let bookId: String?
    public let chapterNumber: Int?
    public let tone: ToneKey?

    public init(
        sessionId: String?,
        attemptNumber: Int? = nil,
        nextAttemptNumber: Int? = nil,
        status: QuizSessionStatus? = nil,
        questions: [QuizQuestion],
        passingScorePercent: Int?,
        bookId: String?,
        chapterNumber: Int?,
        tone: ToneKey?
    ) {
        self.sessionId = sessionId
        self.attemptNumber = attemptNumber
        self.nextAttemptNumber = nextAttemptNumber
        self.status = status
        self.questions = questions
        self.passingScorePercent = passingScorePercent
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.tone = tone
    }
}

/// Lifecycle state returned by the quiz session projection.
public enum QuizSessionStatus: Codable, Sendable, Equatable {
    case ready
    case cooldown
    case passed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "ready": self = .ready
        case "cooldown": self = .cooldown
        case "passed": self = .passed
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .ready: "ready"
        case .cooldown: "cooldown"
        case .passed: "passed"
        case .unknown(let value): value
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A single quiz question with a server-managed choice-ID scheme.
public struct QuizQuestion: Codable, Sendable, Identifiable, Equatable {
    public let questionId: String
    /// The question text. The server may use either `prompt` or `stem`; we unify them.
    public let prompt: String
    public let choices: [QuizChoice]

    public var id: String { questionId }

    public init(questionId: String, prompt: String, choices: [QuizChoice]) {
        self.questionId = questionId
        self.prompt = prompt
        self.choices = choices
    }

    enum CodingKeys: String, CodingKey {
        case questionId, prompt, stem, choices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questionId = try c.decode(String.self, forKey: .questionId)
        choices = try c.decode([QuizChoice].self, forKey: .choices)
        // Prefer `prompt`; fall back to `stem` for older server versions.
        if let p = try? c.decode(String.self, forKey: .prompt) {
            prompt = p
        } else {
            prompt = try c.decode(String.self, forKey: .stem)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(questionId, forKey: .questionId)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(choices, forKey: .choices)
    }
}

/// A single answer choice presented to the user.
public struct QuizChoice: Codable, Sendable, Identifiable, Equatable {
    public let choiceId: String
    public let text: String

    public var id: String { choiceId }

    public init(choiceId: String, text: String) {
        self.choiceId = choiceId
        self.text = text
    }
}
