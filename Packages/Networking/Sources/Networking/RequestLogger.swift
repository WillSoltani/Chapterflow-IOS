import Foundation
import os

/// A hook the ``APIClient`` calls to observe outgoing requests and incoming
/// responses. Kept as a protocol so tests can assert on traffic and release
/// builds can plug in a no-op.
public protocol RequestLogging: Sendable {
    func logRequest(_ request: URLRequest)
    func logResponse(_ response: HTTPURLResponse, data: Data, for request: URLRequest)
    func logFailure(_ error: Error, for request: URLRequest)
}

/// A privacy-aware, debug-only request logger built on `os.Logger`.
///
/// In release builds the methods are no-ops (guarded by `#if DEBUG`) so no
/// request metadata is emitted in production. The Authorization header is never
/// logged.
public struct DebugRequestLogger: RequestLogging {
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "Networking")

    public init() {}

    public func logRequest(_ request: URLRequest) {
        #if DEBUG
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        logger.debug("→ \(method, privacy: .public) \(url, privacy: .public)")
        #endif
    }

    public func logResponse(_ response: HTTPURLResponse, data: Data, for request: URLRequest) {
        #if DEBUG
        let url = request.url?.absoluteString ?? "?"
        logger.debug("← \(response.statusCode, privacy: .public) \(url, privacy: .public) (\(data.count, privacy: .public) bytes)")
        #endif
    }

    public func logFailure(_ error: Error, for request: URLRequest) {
        #if DEBUG
        let url = request.url?.absoluteString ?? "?"
        logger.debug("✗ \(url, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        #endif
    }
}
