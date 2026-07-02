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

    @Test("requestCompleted adds a network breadcrumb without PII")
    func requestCompletedBreadcrumb() {
        var captured: CrashBreadcrumb?
        let spy = SpyCrashReporter { crumb in captured = crumb }
        let obs = CrashBreadcrumbAPIObserver(reporter: spy)

        obs.requestCompleted(
            method: "GET",
            path: "/book/books/b1",
            status: 200,
            requestId: "req-abc"
        )

        let crumb = try! #require(captured)
        #expect(crumb.category == "network")
        #expect(crumb.message.contains("GET"))
        #expect(crumb.message.contains("/book/books/b1"))
        #expect(crumb.message.contains("200"))
        #expect(crumb.metadata["requestId"] == "req-abc")
    }

    @Test("requestCompleted with 5xx produces an error-level breadcrumb")
    func serverErrorLevel() {
        var captured: CrashBreadcrumb?
        let spy = SpyCrashReporter { crumb in captured = crumb }
        let obs = CrashBreadcrumbAPIObserver(reporter: spy)
        obs.requestCompleted(method: "POST", path: "/book/me", status: 500, requestId: nil)
        #expect(captured?.level == .error)
    }

    @Test("requestFailed adds an error-level network breadcrumb")
    func requestFailedBreadcrumb() {
        var captured: CrashBreadcrumb?
        let spy = SpyCrashReporter { crumb in captured = crumb }
        let obs = CrashBreadcrumbAPIObserver(reporter: spy)
        obs.requestFailed(method: "GET", path: "/book/me", error: URLError(.timedOut))
        #expect(captured?.level == .error)
        #expect(captured?.category == "network")
    }

    @Test("breadcrumb message never contains a Bearer token")
    func noBearerTokenInBreadcrumb() {
        var captured: CrashBreadcrumb?
        let spy = SpyCrashReporter { crumb in captured = crumb }
        let obs = CrashBreadcrumbAPIObserver(reporter: spy)
        // Even if someone accidentally passes a token in path (defensive test)
        obs.requestCompleted(
            method: "GET",
            path: "/book/Bearer eyJabc.def.ghi",
            status: 200,
            requestId: nil
        )
        #expect(!(captured?.message.contains("eyJabc.def.ghi") ?? true))
    }
}

// MARK: - Spy

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
