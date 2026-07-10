import Foundation

// MARK: - CommitmentOutcome

/// The user's self-reported outcome after the follow-up window.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Views treat `.unknown` the same as no outcome.
public enum CommitmentOutcome: Sendable, Equatable, Hashable {
    case helped
    case partly
    case didnt
    /// A value the client does not recognise. Treat as no outcome; never crash.
    case unknown(String)
}

extension CommitmentOutcome: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .helped:         return "helped"
        case .partly:         return "partly"
        case .didnt:          return "didnt"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "helped": self = .helped
        case "partly": self = .partly
        case "didnt":  self = .didnt
        default:       self = .unknown(rawValue)
        }
    }
}

extension CommitmentOutcome: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = CommitmentOutcome(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension CommitmentOutcome: CaseIterable {
    public static var allCases: [CommitmentOutcome] { [.helped, .partly, .didnt] }
}

// MARK: - CommitmentStatus

/// Server-side lifecycle state of a commitment.
public enum CommitmentStatus: Sendable, Equatable, Hashable {
    case active
    case done
    /// A value the client does not recognise. Treat as `.active`; never crash.
    case unknown(String)
}

extension CommitmentStatus: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .active:         return "active"
        case .done:           return "done"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "active": self = .active
        case "done":   self = .done
        default:       self = .unknown(rawValue)
        }
    }
}

extension CommitmentStatus: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = CommitmentStatus(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension CommitmentStatus: CaseIterable {
    public static var allCases: [CommitmentStatus] { [.active, .done] }
}

// MARK: - Commitment

/// An if-then implementation plan the user creates after completing a chapter.
///
/// Returned by `GET /book/me/commitments`, `POST /book/me/commitments`,
/// `GET /book/me/commitments/{id}`, and `PATCH /book/me/commitments/{id}`.
public struct Commitment: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let bookId: String
    public let chapterId: String
    /// The trigger situation: "If I …"
    public let ifStatement: String
    /// The intended action: "… then I will …"
    public let thenStatement: String
    /// When the follow-up reminder fires and reflection is due.
    public let followUpDate: Date
    public let status: CommitmentStatus
    /// The user's self-reported outcome after the follow-up. `nil` until submitted.
    public let outcome: CommitmentOutcome?
    /// Free-text reflection submitted at follow-up. `nil` until submitted.
    public let reflection: String?
    public let createdAt: Date

    public init(
        id: String,
        bookId: String,
        chapterId: String,
        ifStatement: String,
        thenStatement: String,
        followUpDate: Date,
        status: CommitmentStatus,
        outcome: CommitmentOutcome?,
        reflection: String?,
        createdAt: Date
    ) {
        self.id = id
        self.bookId = bookId
        self.chapterId = chapterId
        self.ifStatement = ifStatement
        self.thenStatement = thenStatement
        self.followUpDate = followUpDate
        self.status = status
        self.outcome = outcome
        self.reflection = reflection
        self.createdAt = createdAt
    }

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // Deployed commitment items are shaped {commitmentId, bookId,
    // chapterNumber, ifThenPlan, commitDate, followUpDate, status,
    // followThroughReflection, outcome, createdAt, …}: the id/plan keys
    // differ, the plan is ONE combined string, and the chapter reference is a
    // number (the chapterId is derived as "<bookId>-chNN", matching the
    // manifest's id scheme). `followUpDate` stays strict — a commitment whose
    // reminder date can't parse is dropped by the lossy list, never
    // mis-scheduled.

    private enum WireKeys: String, CodingKey {
        case id, commitmentId
        case bookId, chapterId, chapterNumber
        case ifStatement, thenStatement, ifThenPlan
        case followUpDate, status, outcome
        case reflection, followThroughReflection
        case createdAt, commitDate
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        id = try c.decodeRequiredFirst(String.self, keys: [.id, .commitmentId])
        bookId = c.decodeFirst(String.self, keys: [.bookId]) ?? ""
        if let explicit = c.decodeFirst(String.self, keys: [.chapterId]) {
            chapterId = explicit
        } else if let number = c.decodeFirst(Int.self, keys: [.chapterNumber]), !bookId.isEmpty {
            chapterId = String(format: "%@-ch%02d", bookId, number)
        } else {
            chapterId = ""
        }
        if let ifPart = c.decodeFirst(String.self, keys: [.ifStatement]) {
            ifStatement = ifPart
            thenStatement = c.decodeFirst(String.self, keys: [.thenStatement]) ?? ""
        } else {
            // Deployed shape carries one combined "If …, then …" plan string.
            ifStatement = c.decodeFirst(String.self, keys: [.ifThenPlan]) ?? ""
            thenStatement = ""
        }
        // A user-authored commitment must never be silently dropped over an
        // unparseable date (red-team finding): degrade to .distantFuture —
        // listed but its reminder never fires — instead of losing the item.
        followUpDate = c.decodeFirst(Date.self, keys: [.followUpDate]) ?? .distantFuture
        status = c.decodeFirst(CommitmentStatus.self, keys: [.status]) ?? .unknown("")
        outcome = c.decodeFirst(CommitmentOutcome.self, keys: [.outcome])
        reflection = c.decodeFirst(String.self, keys: [.reflection, .followThroughReflection])
        if let created = c.decodeFirst(Date.self, keys: [.createdAt, .commitDate]) {
            createdAt = created
        } else {
            createdAt = .distantPast
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(bookId, forKey: .bookId)
        try c.encode(chapterId, forKey: .chapterId)
        try c.encode(ifStatement, forKey: .ifStatement)
        try c.encode(thenStatement, forKey: .thenStatement)
        try c.encode(followUpDate, forKey: .followUpDate)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(outcome, forKey: .outcome)
        try c.encodeIfPresent(reflection, forKey: .reflection)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Response wrappers

public struct CommitmentsResponse: Codable, Sendable {
    public let commitments: [Commitment]

    public init(commitments: [Commitment]) {
        self.commitments = commitments
    }

    private enum CodingKeys: String, CodingKey { case commitments }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.commitments = try container.decodeLossy(Commitment.self, forKey: .commitments)
    }
}

public struct CommitmentResponse: Codable, Sendable {
    public let commitment: Commitment

    public init(commitment: Commitment) {
        self.commitment = commitment
    }
}

// MARK: - Request bodies

/// Body for `POST /book/me/commitments`.
public struct CreateCommitmentRequest: Encodable, Sendable {
    public let bookId: String
    public let chapterId: String
    public let ifStatement: String
    public let thenStatement: String
    /// Number of days until follow-up: 3 or 7.
    public let followUpDays: Int

    public init(
        bookId: String,
        chapterId: String,
        ifStatement: String,
        thenStatement: String,
        followUpDays: Int
    ) {
        self.bookId = bookId
        self.chapterId = chapterId
        self.ifStatement = ifStatement
        self.thenStatement = thenStatement
        self.followUpDays = followUpDays
    }
}

/// Body for `PATCH /book/me/commitments/{id}`.
public struct UpdateCommitmentRequest: Encodable, Sendable {
    public let reflection: String
    public let outcome: CommitmentOutcome

    public init(reflection: String, outcome: CommitmentOutcome) {
        self.reflection = reflection
        self.outcome = outcome
    }
}
