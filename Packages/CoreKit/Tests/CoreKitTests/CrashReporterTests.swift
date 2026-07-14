import Testing
import Foundation
@testable import CoreKit

@Suite("PIIScrubber")
struct PIIScrubberTests {

    @Test("email addresses are replaced with [email]")
    func scrubsEmail() {
        let input = "User alice@example.com signed in"
        let result = PIIScrubber.scrub(input)
        #expect(!result.contains("alice@example.com"))
        #expect(result.contains("[email]"))
    }

    @Test("multiple emails in one string are all replaced")
    func scrubsMultipleEmails() {
        let input = "from: a@b.com to: c@d.org"
        let result = PIIScrubber.scrub(input)
        #expect(!result.contains("a@b.com"))
        #expect(!result.contains("c@d.org"))
        #expect(result.components(separatedBy: "[email]").count == 3) // two replacements
    }

    @Test("Bearer token is replaced with [token]")
    func scrubsBearerToken() {
        let input = "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.abc.def"
        let result = PIIScrubber.scrub(input)
        #expect(!result.contains("eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"))
        #expect(result.contains("[token]"))
        #expect(result.contains("Bearer"))
    }

    @Test("bearer is case-insensitive")
    func scrubsBearerCaseInsensitive() {
        let input = "BEARER sometoken123"
        let result = PIIScrubber.scrub(input)
        #expect(!result.contains("sometoken123"))
        #expect(result.contains("[token]"))
    }

    @Test("plain text without PII is unchanged")
    func noOpOnSafeString() {
        let input = "GET /book/books/b1 → 200"
        #expect(PIIScrubber.scrub(input) == input)
    }

    @Test("dictionary values are all scrubbed")
    func scrubsDictionary() {
        let dict = [
            "path": "/books",
            "user": "alice@example.com",
            "token": "Bearer abc.def.ghi",
        ]
        let result = PIIScrubber.scrub(dict)
        #expect(result["user"] == "[email]")
        #expect(!result["token"]!.contains("abc.def.ghi"))
        #expect(result["path"] == "/books")
    }

    @Test("CrashBreadcrumb scrubs message at init time")
    func breadcrumbScrubsAtInit() {
        let crumb = CrashBreadcrumb(
            category: "auth",
            message: "token: Bearer eyJ.abc.def for user@test.com",
            level: .info
        )
        #expect(!crumb.message.contains("eyJ.abc.def"))
        #expect(!crumb.message.contains("user@test.com"))
    }

    @Test("CrashBreadcrumb scrubs metadata at init time")
    func breadcrumbScrubsMetadata() {
        let crumb = CrashBreadcrumb(
            category: "network",
            message: "GET /books → 200",
            level: .info,
            metadata: ["auth": "Bearer realtoken", "user": "alice@example.com"]
        )
        #expect(!crumb.metadata["auth"]!.contains("realtoken"))
        #expect(!crumb.metadata["user"]!.contains("alice@example.com"))
    }
}

@Suite("CrashReporterFactory")
struct CrashReporterFactoryTests {

    @Test("empty DSN produces NoopCrashReporter (compiles and runs silently)")
    func emptyDSNProducesNoop() {
        let reporter = CrashReporterFactory.make(dsn: "")
        // NoopCrashReporter: all calls are silent, nothing throws or crashes.
        reporter.setUser(id: "user-123")
        reporter.addBreadcrumb(CrashBreadcrumb(category: "test", message: "hello"))
        reporter.captureError(AppError.offline, context: ["key": "value"])
        reporter.captureMessage("test message", level: .info)
        reporter.setUser(id: nil)
    }

    @Test("NoopCrashReporter conforms to CrashReporter and does nothing")
    func noopCompiles() {
        let reporter: any CrashReporter = NoopCrashReporter()
        reporter.setUser(id: "abc")
        reporter.addBreadcrumb(CrashBreadcrumb(category: "nav", message: "pushed"))
        reporter.captureError(AppError.notFound, context: [:])
        reporter.captureMessage("noop", level: .debug)
    }
}

@Suite("CrashBreadcrumbAPIObserver")
struct CrashBreadcrumbAPIObserverTests {

    @Test("typed success observation adds only allowlisted breadcrumb fields")
    func successBreadcrumb() {
        var captured: CrashBreadcrumb?
        let spy = SpyCrashReporter { crumb in captured = crumb }
        let obs = CrashBreadcrumbAPIObserver(reporter: spy)

        obs.record(APIRequestObservation(
            method: .get,
            route: "/book/books/private-book-id",
            attempt: 2,
            elapsed: .milliseconds(720),
            outcome: .success,
            statusCode: 200,
            requestId: "req-observe1234567890",
            retryDisposition: .final
        ))

        let crumb = try! #require(captured)
        #expect(crumb.category == "network")
        #expect(crumb.level == .info)
        #expect(crumb.message == "GET /book/books/:id success")
        #expect(crumb.metadata == [
            "attempt": "2",
            "duration": "500ms_to_1s",
            "method": "GET",
            "outcome": "success",
            "requestId": "req-observe1234567890",
            "retry": "final",
            "route": "/book/books/:id",
            "status": "200",
        ])
        #expect(crumb.metadata["requestId"] == "req-observe1234567890")
        #expect(!crumb.message.contains("private-book-id"))
    }

    @Test("HTTP 5xx produces an error-level breadcrumb")
    func serverErrorLevel() {
        var captured: CrashBreadcrumb?
        let spy = SpyCrashReporter { crumb in captured = crumb }
        let obs = CrashBreadcrumbAPIObserver(reporter: spy)
        obs.record(APIRequestObservation(
            method: .post,
            route: "/book/me",
            attempt: 1,
            elapsed: .milliseconds(20),
            outcome: .httpFailure,
            statusCode: 500,
            requestId: nil,
            retryDisposition: .final
        ))
        #expect(captured?.level == .error)
    }

    @Test("cancellation is never an error-level breadcrumb")
    func cancellationLevel() {
        var captured: CrashBreadcrumb?
        let spy = SpyCrashReporter { crumb in captured = crumb }
        let obs = CrashBreadcrumbAPIObserver(reporter: spy)
        obs.record(APIRequestObservation(
            method: .get,
            route: "/book/me/export",
            attempt: 1,
            elapsed: .milliseconds(5),
            outcome: .cancellation,
            statusCode: nil,
            requestId: nil,
            retryDisposition: .final
        ))
        #expect(captured?.level == .info)
        #expect(captured?.category == "network")
        #expect(captured?.metadata["outcome"] == "cancellation")
    }

    @Test("breadcrumb reflection cannot contain URL, query, token, body, identifier, or raw error")
    func breadcrumbPrivacyBoundary() {
        var captured: CrashBreadcrumb?
        let spy = SpyCrashReporter { crumb in captured = crumb }
        let obs = CrashBreadcrumbAPIObserver(reporter: spy)
        let forbiddenValues = [
            "private-book-id",
            "private-query",
            "Bearer private-token",
            "private-body",
            "alice@example.com",
            "URLError",
            "timedOut",
        ]

        obs.record(APIRequestObservation(
            method: .get,
            route: "/book/books/private-book-id?query=private-query#Bearer%20private-token",
            attempt: 1,
            elapsed: .milliseconds(10),
            outcome: .networkFailure,
            statusCode: nil,
            requestId: "alice@example.com/private-body/URLError/timedOut",
            retryDisposition: .final
        ))

        let crumb = try! #require(captured)
        let reflected = String(reflecting: crumb)
        for value in forbiddenValues {
            #expect(!reflected.contains(value))
        }
        #expect(crumb.message == "GET /book/books/:id network_failure")
    }

    @Test("no-op observer accepts typed events without side effects")
    func noopObserver() {
        let observer: any APIClientObserver = NoopAPIClientObserver()
        observer.record(APIRequestObservation(
            method: .delete,
            route: "/book/me/notebook/private-entry",
            attempt: 1,
            elapsed: .zero,
            outcome: .success,
            statusCode: 204,
            requestId: nil,
            retryDisposition: .final
        ))
    }
}

// MARK: - MetricKitCrashSubscriber analytics wiring

#if os(iOS)
@Suite("MetricKitCrashSubscriber")
struct MetricKitCrashSubscriberTests {

    @Test("initialises with analytics and reporter without crashing")
    func initWithAnalytics() {
        let reporter = NoopCrashReporter()
        let analytics = SpyAnalyticsClient()
        let subscriber = MetricKitCrashSubscriber(reporter: reporter, analytics: analytics)
        // Just verify the object is created — `register()` requires a real device.
        #expect(subscriber != nil)
    }

    @Test("initialises with nil analytics (backward compatibility)")
    func initWithoutAnalytics() {
        let reporter = NoopCrashReporter()
        let subscriber = MetricKitCrashSubscriber(reporter: reporter)
        #expect(subscriber != nil)
    }
}
#endif

// MARK: - Spies

/// A test double that captures breadcrumbs added to a crash reporter.
private final class SpyCrashReporter: CrashReporter, @unchecked Sendable {
    private let onBreadcrumb: (CrashBreadcrumb) -> Void

    init(onBreadcrumb: @escaping (CrashBreadcrumb) -> Void) {
        self.onBreadcrumb = onBreadcrumb
    }

    func setUser(id: String?) {}
    func addBreadcrumb(_ breadcrumb: CrashBreadcrumb) { onBreadcrumb(breadcrumb) }
    func captureError(_ error: any Error, context: [String: String]) {}
    func captureMessage(_ message: String, level: CrashBreadcrumb.Level) {}
}

/// A test double that records tracked analytics events.
private final class SpyAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    private(set) var tracked: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { tracked.append(event) }
    func beacon(_ name: String, properties: [String: String]) {}
    func flush() async {}
}
