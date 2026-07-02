import Foundation

// MARK: - Protocol

/// A hook the `APIClient` (in Networking) calls after every HTTP exchange.
///
/// Defined in CoreKit so Networking can reference it without creating a
/// circular dependency. Implementations receive only safe, non-PII fields:
/// method, path (no query string), status, and the optional server requestId
/// from error envelopes. Request/response bodies and auth tokens are never
/// exposed.
public protocol APIClientObserver: Sendable {
    /// Called after every completed HTTP exchange — whether the status was
    /// 2xx or an error. For retried requests, called after *each* attempt.
    ///
    /// - Parameters:
    ///   - method: HTTP verb (e.g. `"GET"`, `"POST"`).
    ///   - path: Request path only (e.g. `"/book/books/b1"`), never including
    ///     a query string or fragment that could carry PII.
    ///   - status: HTTP status code.
    ///   - requestId: The server's `requestId` from the error envelope, if any.
    func requestCompleted(method: String, path: String, status: Int, requestId: String?)

    /// Called when a request fails with a network-layer error (no HTTP response).
    func requestFailed(method: String, path: String, error: any Error)
}

// MARK: - Crash breadcrumb adapter

/// Bridges ``APIClientObserver`` into crash-report breadcrumbs via a
/// ``CrashReporter``. Wire this up at the composition root when creating
/// `APIClient`.
public struct CrashBreadcrumbAPIObserver: APIClientObserver {
    private let reporter: any CrashReporter

    public init(reporter: any CrashReporter) {
        self.reporter = reporter
    }

    public func requestCompleted(method: String, path: String, status: Int, requestId: String?) {
        var meta: [String: String] = [
            "method": method,
            "status": String(status),
        ]
        if let requestId { meta["requestId"] = requestId }

        let level: CrashBreadcrumb.Level = status >= 500 ? .error
            : status >= 400 ? .warning
            : .info

        reporter.addBreadcrumb(CrashBreadcrumb(
            category: "network",
            message: "\(method) \(path) → \(status)",
            level: level,
            metadata: meta
        ))
    }

    public func requestFailed(method: String, path: String, error: any Error) {
        reporter.addBreadcrumb(CrashBreadcrumb(
            category: "network",
            message: "\(method) \(path) → \(type(of: error))",
            level: .error,
            metadata: ["method": method]
        ))
    }
}

// MARK: - Noop

/// A no-op ``APIClientObserver`` for tests and previews.
public struct NoopAPIClientObserver: APIClientObserver {
    public init() {}
    public func requestCompleted(method: String, path: String, status: Int, requestId: String?) {}
    public func requestFailed(method: String, path: String, error: any Error) {}
}
