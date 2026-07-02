import Foundation
import Sentry

/// The Sentry-backed ``CrashReporter``.
///
/// This type is `internal` — it is never exported from CoreKit. All external
/// code works through the ``CrashReporter`` protocol obtained via
/// ``CrashReporterFactory/make(dsn:environment:)``. No symbol from the Sentry
/// SDK is visible outside this file.
final class SentryCrashReporter: CrashReporter, @unchecked Sendable {

    init(dsn: String, environment: String) {
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            options.enableCrashHandler = true
            options.attachStacktrace = true
            // Never forward PII to Sentry servers automatically.
            options.sendDefaultPii = false
            // Belt-and-suspenders: scrub anything that slipped through.
            options.beforeSend = { event in
                SentryCrashReporter.cleanEvent(event)
                return event
            }
        }
    }

    func setUser(id: String?) {
        if let id {
            let user = Sentry.User(userId: id)
            SentrySDK.setUser(user)
        } else {
            SentrySDK.setUser(nil)
        }
    }

    func addBreadcrumb(_ crumb: CrashBreadcrumb) {
        // CrashBreadcrumb.init already ran PIIScrubber at construction time.
        let b = Breadcrumb(level: crumb.level.sentryLevel, category: crumb.category)
        b.type = "default"
        b.message = crumb.message
        b.data = crumb.metadata
        SentrySDK.addBreadcrumb(b)
    }

    func captureError(_ error: any Error, context: [String: String]) {
        let scrubbed = PIIScrubber.scrub(context)
        SentrySDK.capture(error: error) { scope in
            for (key, value) in scrubbed {
                scope.setExtra(value: value, key: key)
            }
        }
    }

    func captureMessage(_ message: String, level: CrashBreadcrumb.Level) {
        let scrubbed = PIIScrubber.scrub(message)
        SentrySDK.capture(message: scrubbed) { scope in
            scope.setLevel(level.sentryLevel)
        }
    }

    // MARK: - Private

    /// Scrubs PII from a Sentry `Event` in the `beforeSend` callback.
    private static func cleanEvent(_ event: Event) {
        event.breadcrumbs = event.breadcrumbs?.map { crumb in
            if let msg = crumb.message { crumb.message = PIIScrubber.scrub(msg) }
            if let data = crumb.data {
                crumb.data = data.reduce(into: [String: Any]()) { result, pair in
                    if let str = pair.value as? String {
                        result[pair.key] = PIIScrubber.scrub(str)
                    } else {
                        result[pair.key] = pair.value
                    }
                }
            }
            return crumb
        }
        if let extras = event.extra {
            event.extra = extras.reduce(into: [String: Any]()) { result, pair in
                if let str = pair.value as? String {
                    result[pair.key] = PIIScrubber.scrub(str)
                } else {
                    result[pair.key] = pair.value
                }
            }
        }
    }
}

private extension CrashBreadcrumb.Level {
    var sentryLevel: SentryLevel {
        switch self {
        case .debug:    return .debug
        case .info:     return .info
        case .warning:  return .warning
        case .error:    return .error
        case .critical: return .fatal
        }
    }
}
