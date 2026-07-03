import Foundation
import os

/// A thin, privacy-aware wrapper over `os.Logger`.
///
/// Use one `AppLog` per subsystem area (`Category`). String messages are logged
/// as `.public` by default, while the `private:` overloads keep potentially
/// sensitive values redacted in release builds. Never log raw PII — use
/// `AppLog.redact(_:)` or the `private:` overloads for anything user-identifying.
public struct AppLog: Sendable {
    /// The default unified-logging subsystem for the whole app.
    public static let subsystem = "com.chapterflow.ios"

    /// Logical areas of the app, used as the `os.Logger` category.
    public enum Category: String, Sendable, CaseIterable {
        case app
        case network
        case auth
        case reader
        case analytics
        case persistence
        case sync
        case ui
        case notifications
        case billing
    }

    private let logger: os.Logger

    public init(category: Category) {
        self.logger = os.Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    public init(subsystem: String = AppLog.subsystem, category: String) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    // MARK: - Public messages (safe, non-PII)

    public func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    public func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    public func notice(_ message: String) { logger.notice("\(message, privacy: .public)") }
    public func warning(_ message: String) { logger.warning("\(message, privacy: .public)") }
    public func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    public func fault(_ message: String) { logger.fault("\(message, privacy: .public)") }

    // MARK: - Privacy-aware messages

    /// Logs a public label alongside a value kept `.private` (redacted in release).
    public func debug(_ label: String, private value: String) {
        logger.debug("\(label, privacy: .public): \(value, privacy: .private)")
    }

    public func info(_ label: String, private value: String) {
        logger.info("\(label, privacy: .public): \(value, privacy: .private)")
    }

    public func error(_ label: String, private value: String) {
        logger.error("\(label, privacy: .public): \(value, privacy: .private)")
    }

    /// Logs an `AppError` using its non-sensitive `code` only.
    public func error(_ label: String, _ appError: AppError) {
        logger.error("\(label, privacy: .public): \(appError.code, privacy: .public)")
    }

    // MARK: - Redaction helper

    /// Masks a string for safe inclusion in a `.public` message, keeping only the
    /// last `keepingLast` characters visible (e.g. `redact("secret", keepingLast: 2)`
    /// → `"••••et"`). An empty input yields an empty string.
    public static func redact(_ value: String, keepingLast keep: Int = 0) -> String {
        guard !value.isEmpty else { return "" }
        let keep = max(0, min(keep, value.count))
        let visibleCount = keep
        let maskedCount = value.count - visibleCount
        let masked = String(repeating: "•", count: maskedCount)
        let tail = visibleCount > 0 ? String(value.suffix(visibleCount)) : ""
        return masked + tail
    }

    /// Redacts an email to `••••@domain.com`, preserving only the domain.
    public static func redactEmail(_ email: String) -> String {
        guard let at = email.firstIndex(of: "@") else { return redact(email) }
        let domain = email[email.index(after: at)...]
        return "••••@\(domain)"
    }
}
