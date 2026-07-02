import Foundation

// MARK: - Breadcrumb

/// A breadcrumb attached to crash reports for trail-of-events context.
public struct CrashBreadcrumb: Sendable {
    public enum Level: String, Sendable {
        case debug, info, warning, error, critical
    }

    /// Logical category (e.g. `"network"`, `"navigation"`, `"auth"`).
    public let category: String
    /// Human-readable description — must never contain tokens or email addresses.
    public let message: String
    public let level: Level
    /// Structured metadata, scrubbed before reaching any external sink.
    public let metadata: [String: String]

    public init(
        category: String,
        message: String,
        level: Level = .info,
        metadata: [String: String] = [:]
    ) {
        self.category = category
        self.message = PIIScrubber.scrub(message)
        self.level = level
        self.metadata = PIIScrubber.scrub(metadata)
    }
}

// MARK: - Protocol

/// Vendor-swappable crash reporting and breadcrumb interface.
///
/// Nothing outside CoreKit imports the concrete vendor SDK (Sentry). Callers
/// depend only on this protocol; obtain an instance via
/// ``CrashReporterFactory/make(dsn:environment:)``.
public protocol CrashReporter: Sendable {
    /// Configures the reporter for a signed-in user. Pass the Cognito `sub`
    /// (never email, name, or any other PII).
    func setUser(id: String?)
    /// Records a breadcrumb for the trail-of-events leading to a crash.
    func addBreadcrumb(_ breadcrumb: CrashBreadcrumb)
    /// Captures a non-fatal error for diagnostic review.
    func captureError(_ error: any Error, context: [String: String])
    /// Captures a non-fatal message.
    func captureMessage(_ message: String, level: CrashBreadcrumb.Level)
}

// MARK: - Noop

/// A no-op ``CrashReporter`` for empty DSN, tests, and previews.
public struct NoopCrashReporter: CrashReporter {
    public init() {}
    public func setUser(id: String?) {}
    public func addBreadcrumb(_ breadcrumb: CrashBreadcrumb) {}
    public func captureError(_ error: any Error, context: [String: String]) {}
    public func captureMessage(_ message: String, level: CrashBreadcrumb.Level) {}
}

// MARK: - Factory

/// Creates the appropriate ``CrashReporter`` for the given DSN.
///
/// An empty `dsn` string produces a ``NoopCrashReporter`` with zero overhead.
/// All Sentry symbols remain confined to CoreKit internals.
public enum CrashReporterFactory {
    /// - Parameters:
    ///   - dsn: Sentry project DSN. Pass an empty string to fully disable.
    ///   - environment: Sentry environment tag (e.g. `"production"`, `"staging"`).
    public static func make(dsn: String, environment: String = "production") -> any CrashReporter {
        guard !dsn.isEmpty else { return NoopCrashReporter() }
        return SentryCrashReporter(dsn: dsn, environment: environment)
    }
}

// MARK: - PII Scrubbing

/// Strips PII from strings before they reach any external sink.
///
/// Applied at every call site that produces breadcrumb/event data so that
/// the constraint "no email or token appears in any payload" is enforced
/// close to the source rather than relying on an after-the-fact SDK hook.
public enum PIIScrubber {
    private static let emailPattern =
        #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
    private static let bearerPattern =
        #"(?i)(Bearer\s+)[A-Za-z0-9\._\-]+"#

    private static let emailRegex: NSRegularExpression = {
        // Regex is a constant literal; try! is safe here.
        try! NSRegularExpression(pattern: emailPattern)
    }()

    private static let bearerRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: bearerPattern)
    }()

    /// Replaces email addresses and Bearer tokens with safe placeholders.
    public static func scrub(_ value: String) -> String {
        var result = value
        let full = NSRange(result.startIndex..., in: result)
        result = emailRegex.stringByReplacingMatches(
            in: result, range: full, withTemplate: "[email]"
        )
        let full2 = NSRange(result.startIndex..., in: result)
        result = bearerRegex.stringByReplacingMatches(
            in: result, range: full2, withTemplate: "$1[token]"
        )
        return result
    }

    /// Scrubs all values in a string dictionary.
    public static func scrub(_ dict: [String: String]) -> [String: String] {
        dict.mapValues { scrub($0) }
    }
}
