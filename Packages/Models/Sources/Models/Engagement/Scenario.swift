import Foundation

// MARK: - ScenarioScope

/// The real-world context the user chose for their application scenario.
///
/// Server-evolution contract: unknown values decode to `.unknown(rawValue)`.
public enum ScenarioScope: Sendable, Equatable, Hashable, CaseIterable {
    case work
    case school
    case personal
    case unknown(String)

    public static var allCases: [ScenarioScope] { [.work, .school, .personal] }
}

extension ScenarioScope: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .work:          return "work"
        case .school:        return "school"
        case .personal:      return "personal"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "work":     self = .work
        case "school":   self = .school
        case "personal": self = .personal
        default:         self = .unknown(rawValue)
        }
    }
}

extension ScenarioScope: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ScenarioScope(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - ScenarioStatus

/// The AI + moderation status for a submitted scenario.
///
/// Server-evolution contract: unknown values decode to `.unknown(rawValue)`.
public enum ScenarioStatus: Sendable, Equatable, Hashable {
    case pending
    case approved
    case rejected
    case unknown(String)
}

extension ScenarioStatus: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .pending:        return "pending"
        case .approved:       return "approved"
        case .rejected:       return "rejected"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "pending":  self = .pending
        case "approved": self = .approved
        case "rejected": self = .rejected
        default:         self = .unknown(rawValue)
        }
    }
}

extension ScenarioStatus: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ScenarioStatus(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - UserScenario

/// A scenario the authenticated user submitted for a chapter.
///
/// Returned by `GET /book/me/books/{bookId}/chapters/{n}/scenarios`
/// and `POST /book/me/books/{bookId}/chapters/{n}/scenarios`.
public struct UserScenario: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let bookId: String
    public let chapterNumber: Int
    public let title: String
    public let scenario: String
    public let whatToDo: String
    public let whyItMatters: String
    public let scope: ScenarioScope
    public let status: ScenarioStatus
    /// Flow-points awarded by the server on approval. `nil` until approved.
    public let pointsAwarded: Int?
    public let createdAt: Date

    public init(
        id: String,
        bookId: String,
        chapterNumber: Int,
        title: String,
        scenario: String,
        whatToDo: String,
        whyItMatters: String,
        scope: ScenarioScope,
        status: ScenarioStatus,
        pointsAwarded: Int?,
        createdAt: Date
    ) {
        self.id = id
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.title = title
        self.scenario = scenario
        self.whatToDo = whatToDo
        self.whyItMatters = whyItMatters
        self.scope = scope
        self.status = status
        self.pointsAwarded = pointsAwarded
        self.createdAt = createdAt
    }
}

// MARK: - CommunityScenario

/// An approved community scenario for a chapter — shown as inspiration.
///
/// Only present if the server exposes them in the response.
public struct CommunityScenario: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let scenario: String
    public let whatToDo: String
    public let whyItMatters: String
    public let scope: ScenarioScope
    /// Display name for the author. May be anonymous.
    public let authorName: String?
    public let createdAt: Date

    public init(
        id: String,
        title: String,
        scenario: String,
        whatToDo: String,
        whyItMatters: String,
        scope: ScenarioScope,
        authorName: String?,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.scenario = scenario
        self.whatToDo = whatToDo
        self.whyItMatters = whyItMatters
        self.scope = scope
        self.authorName = authorName
        self.createdAt = createdAt
    }
}

// MARK: - Response wrappers

/// Response for `GET /book/me/books/{bookId}/chapters/{n}/scenarios`.
public struct ScenariosResponse: Codable, Sendable {
    public let scenarios: [UserScenario]
    /// Community scenarios may not be present on all server versions.
    public let community: [CommunityScenario]

    public init(scenarios: [UserScenario], community: [CommunityScenario]) {
        self.scenarios = scenarios
        self.community = community
    }

    private enum CodingKeys: String, CodingKey {
        case scenarios
        case community
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.scenarios = try container.decodeLossy(UserScenario.self, forKey: .scenarios)
        self.community = (try? container.decodeLossy(CommunityScenario.self, forKey: .community)) ?? []
    }
}

/// Response for `POST /book/me/books/{bookId}/chapters/{n}/scenarios`.
public struct ScenarioResponse: Codable, Sendable {
    public let scenario: UserScenario

    public init(scenario: UserScenario) {
        self.scenario = scenario
    }
}

// MARK: - Request body

/// Body for `POST /book/me/books/{bookId}/chapters/{n}/scenarios`.
public struct CreateScenarioRequest: Encodable, Sendable {
    public let title: String
    public let scenario: String
    public let whatToDo: String
    public let whyItMatters: String
    public let scope: ScenarioScope

    public init(
        title: String,
        scenario: String,
        whatToDo: String,
        whyItMatters: String,
        scope: ScenarioScope
    ) {
        self.title = title
        self.scenario = scenario
        self.whatToDo = whatToDo
        self.whyItMatters = whyItMatters
        self.scope = scope
    }
}
