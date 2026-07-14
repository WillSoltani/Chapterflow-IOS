import Foundation

/// A synchronous, nonthrowing hook called once for every actual API attempt.
///
/// The only input is a closed, privacy-safe value. Implementations must remain
/// bounded and must not perform JSON encoding, disk or network I/O, or create
/// unbounded tasks. Observation is never allowed to change request behavior.
public protocol APIClientObserver: Sendable {
    func record(_ event: APIRequestObservation)
}

/// Bridges typed API observations into privacy-safe crash breadcrumbs.
public struct CrashBreadcrumbAPIObserver: APIClientObserver {
    private let reporter: any CrashReporter

    public init(reporter: any CrashReporter) {
        self.reporter = reporter
    }

    public func record(_ event: APIRequestObservation) {
        var metadata: [String: String] = [
            "attempt": String(event.attempt),
            "duration": Self.durationBucket(event.elapsed),
            "method": event.method.rawValue,
            "outcome": event.outcome.rawValue,
            "retry": event.retryDisposition.rawValue,
            "route": event.route,
        ]
        if let statusCode = event.statusCode {
            metadata["status"] = String(statusCode)
        }
        if let requestId = event.requestId {
            metadata["requestId"] = requestId
        }

        reporter.addBreadcrumb(CrashBreadcrumb(
            category: "network",
            message: "\(event.method.rawValue) \(event.route) \(event.outcome.rawValue)",
            level: Self.level(for: event),
            metadata: metadata
        ))
    }

    private static func level(for event: APIRequestObservation) -> CrashBreadcrumb.Level {
        switch event.outcome {
        case .success, .cancellation:
            .info
        case .httpFailure:
            if let statusCode = event.statusCode, statusCode >= 500 {
                .error
            } else {
                .warning
            }
        case .networkFailure, .decodingFailure:
            event.retryDisposition == .willRetry ? .warning : .error
        }
    }

    private static func durationBucket(_ elapsed: Duration) -> String {
        if elapsed < .milliseconds(100) {
            "under_100ms"
        } else if elapsed < .milliseconds(500) {
            "100ms_to_500ms"
        } else if elapsed < .seconds(1) {
            "500ms_to_1s"
        } else if elapsed < .seconds(3) {
            "1s_to_3s"
        } else if elapsed < .seconds(10) {
            "3s_to_10s"
        } else {
            "10s_or_more"
        }
    }
}

/// A no-op observer for previews, tests, and composition deferred to WP-OBS-01B.
public struct NoopAPIClientObserver: APIClientObserver {
    public init() {}
    public func record(_ event: APIRequestObservation) {}
}
