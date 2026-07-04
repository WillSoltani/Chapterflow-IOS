import Foundation

// MARK: - ReportReason

/// The reason a user selects when reporting another user or piece of content.
///
/// Carries `.unknown(String)` so future server-added reason codes never crash the
/// app (RF2). Only the statically-known cases appear in the report UI; `.unknown`
/// is a decode-only fallback.
public enum ReportReason: Sendable, Equatable {
    case harassment
    case spam
    case inappropriateContent
    case impersonation
    case other
    /// A reason code the client doesn't recognise — never surfaced in UI.
    case unknown(String)

    /// All cases shown to the user in the report reason picker.
    public static let allDisplayCases: [ReportReason] = [
        .harassment, .spam, .inappropriateContent, .impersonation, .other,
    ]

    public var displayLabel: String {
        switch self {
        case .harassment: return "Harassment or bullying"
        case .spam: return "Spam"
        case .inappropriateContent: return "Inappropriate content"
        case .impersonation: return "Impersonation"
        case .other: return "Other"
        case .unknown: return "Other"
        }
    }

    /// The machine-readable string sent to the server.
    public var rawValue: String {
        switch self {
        case .harassment: return "harassment"
        case .spam: return "spam"
        case .inappropriateContent: return "inappropriate_content"
        case .impersonation: return "impersonation"
        case .other: return "other"
        case .unknown(let raw): return raw
        }
    }
}

extension ReportReason: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "harassment": self = .harassment
        case "spam": self = .spam
        case "inappropriate_content": self = .inappropriateContent
        case "impersonation": self = .impersonation
        case "other": self = .other
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Report request / response

/// Success response body for `POST /book/moderation/reports`.
public struct ReportResponse: Decodable, Sendable {
    /// Server-assigned report ID for support reference.
    public let reportId: String?
    /// Acknowledgement status, e.g. `"received"`.
    public let status: String?
}

// MARK: - Block models

/// A user the current user has blocked.
///
/// ⚠️ Backend TODO: `GET /book/me/blocks` is not yet implemented.
/// Shape: `{ "userId": "<string>", "blockedAt": "<iso8601|null>" }`
public struct BlockedUser: Codable, Sendable, Identifiable, Equatable {
    public var id: String { userId }
    public let userId: String
    /// ISO-8601 timestamp at which the block was placed (server-assigned, may be absent).
    public let blockedAt: String?

    public init(userId: String, blockedAt: String? = nil) {
        self.userId = userId
        self.blockedAt = blockedAt
    }
}

/// Response body for `POST /book/me/blocks` and `DELETE /book/me/blocks/{userId}`.
public struct BlockActionResponse: Decodable, Sendable {
    public let success: Bool?
}

/// Response body for `GET /book/me/blocks`.
public struct BlockedUsersResponse: Decodable, Sendable {
    public let blockedUsers: [BlockedUser]
}
