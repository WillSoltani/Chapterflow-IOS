import Foundation

/// Lightweight snapshot of the authenticated user's identity.
public struct UserSummary: Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let userId: String
    public let username: String
    public let email: String?

    public init(userId: String, username: String, email: String? = nil) {
        self.userId = userId
        self.username = username
        self.email = email
    }

    public var description: String { "UserSummary(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["contents": "redacted"])
    }
}
