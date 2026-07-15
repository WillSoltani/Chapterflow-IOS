import Foundation

/// A closed, privacy-safe error value suitable for rendering in product UI.
///
/// The value deliberately retains no underlying `Error`, localized description,
/// backend message/code, URL, request/response body, token, or product identifier.
/// Dynamic input is reduced to a reviewed category plus an optional correlation ID
/// that passes the same restrictive format used by API observations.
public struct UserFacingError: Error, Sendable, Equatable {
    public enum Category: Sendable, Equatable {
        case connection
        case authentication
        case permission
        case contentUnavailable
        case serviceUnavailable
        case unexpectedResponse
        case compatibility
    }

    public enum Recovery: Sendable, Equatable {
        case retry
        case none
    }

    public enum SupportCode: String, Sendable {
        case connection = "CF-BD-CONNECTION-001"
        case authentication = "CF-BD-AUTH-001"
        case permission = "CF-BD-PERMISSION-001"
        case contentUnavailable = "CF-BD-CONTENT-001"
        case serviceUnavailable = "CF-BD-SERVICE-001"
        case unexpectedResponse = "CF-BD-RESPONSE-001"
        case compatibility = "CF-BD-COMPAT-001"
    }

    public let category: Category
    public let recovery: Recovery
    public let supportCode: SupportCode
    public let requestId: String?

    public init(category: Category, recovery: Recovery = .retry, requestId: String? = nil) {
        self.category = category
        self.recovery = recovery
        self.supportCode = category.supportCode
        self.requestId = Self.safeRequestId(requestId)
    }

    /// Reduces a technical failure to a closed UI value and immediately discards
    /// all unreviewed details. Cancellation remains cancellation and returns `nil`.
    public static func mapping(_ error: any Error) -> UserFacingError? {
        if error is CancellationError { return nil }

        guard let appError = error as? AppError else {
            return UserFacingError(category: .serviceUnavailable)
        }

        switch appError {
        case .unauthenticated, .reauthRequired:
            return UserFacingError(category: .authentication)
        case .forbidden:
            return UserFacingError(category: .permission)
        case .offline:
            return UserFacingError(category: .connection)
        case .notFound:
            return UserFacingError(category: .contentUnavailable)
        case .decoding:
            return UserFacingError(category: .unexpectedResponse)
        case .server(_, _, let requestId):
            return UserFacingError(category: .serviceUnavailable, requestId: requestId)
        case .verifierUnavailable, .rateLimited, .invalidInput:
            return UserFacingError(category: .serviceUnavailable)
        }
    }

    public static let compatibility = UserFacingError(category: .compatibility)

    /// Approved, fixed copy only. Callers never pass arbitrary backend text.
    public var title: String {
        switch category {
        case .connection:
            return "You're Offline"
        case .authentication:
            return "Sign-In Required"
        case .permission:
            return "Access Unavailable"
        case .contentUnavailable:
            return "Book Unavailable"
        case .serviceUnavailable:
            return "Temporarily Unavailable"
        case .unexpectedResponse:
            return "Reading Status Unavailable"
        case .compatibility:
            return "Reading Status Unavailable"
        }
    }

    /// Approved, fixed copy only. Callers never pass arbitrary backend text.
    public var message: String {
        switch category {
        case .connection:
            return "Check your connection and try again."
        case .authentication:
            return "ChapterFlow couldn't verify your account. Try again after signing in."
        case .permission:
            return "ChapterFlow couldn't access this account-backed information."
        case .contentUnavailable:
            return "This book or its current content is no longer available."
        case .serviceUnavailable:
            return "ChapterFlow couldn't load this information right now. Try again in a moment."
        case .unexpectedResponse:
            return "ChapterFlow received an unexpected reading status and won't guess."
        case .compatibility:
            return "ChapterFlow can't safely determine whether this book has been started. Try again."
        }
    }

    private static func safeRequestId(_ requestId: String?) -> String? {
        let prefix = "req-"
        guard let requestId, requestId.hasPrefix(prefix) else { return nil }

        let identifier = requestId.dropFirst(prefix.count)
        guard (16...48).contains(identifier.utf8.count) else { return nil }

        var hasNumber = false
        var hasNonHexLetter = false
        for byte in identifier.utf8 {
            if (48...57).contains(byte) {
                hasNumber = true
            } else if (103...122).contains(byte) {
                hasNonHexLetter = true
            } else if !(97...102).contains(byte) {
                return nil
            }
        }

        return hasNumber && hasNonHexLetter ? requestId : nil
    }
}

private extension UserFacingError.Category {
    var supportCode: UserFacingError.SupportCode {
        switch self {
        case .connection:         return .connection
        case .authentication:     return .authentication
        case .permission:         return .permission
        case .contentUnavailable: return .contentUnavailable
        case .serviceUnavailable: return .serviceUnavailable
        case .unexpectedResponse: return .unexpectedResponse
        case .compatibility:      return .compatibility
        }
    }
}
