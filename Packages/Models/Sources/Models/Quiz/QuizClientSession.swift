/// A quiz client session returned by `GET /book/books/{bookId}/chapters/{n}/quiz`.
///
/// Contains questions for the UI; grading is **always server-side**.
/// Submit selected `choiceId` values to `POST .../submit` — never grade locally.
public struct QuizClientSession: Codable, Sendable {
    public let sessionId: String?
    public let questions: [QuizQuestion]
    public let passingScorePercent: Int?
    public let bookId: String?
    public let chapterNumber: Int?
    public let tone: ToneKey?
}

/// A single quiz question with a server-managed choice-ID scheme.
public struct QuizQuestion: Codable, Sendable, Identifiable {
    public let questionId: String
    /// The question text. The server may use either `prompt` or `stem`; we unify them.
    public let prompt: String
    public let choices: [QuizChoice]

    public var id: String { questionId }

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
public struct QuizChoice: Codable, Sendable, Identifiable {
    public let choiceId: String
    public let text: String

    public var id: String { choiceId }
}
