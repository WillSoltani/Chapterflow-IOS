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
