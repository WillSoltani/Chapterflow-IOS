import Foundation

#if os(iOS)
import MetricKit

/// Subscribes to MetricKit and forwards hang/crash/energy diagnostics into
/// the ``CrashReporter`` pipeline.
///
/// Register once at app launch via ``register()``. MetricKit delivers
/// diagnostic payloads at most once per day, on the day after the events
/// occurred. Payloads are forwarded as non-fatal captures so they can be
/// joined to Sentry issues.
public final class MetricKitCrashSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    private let reporter: any CrashReporter
    private let analytics: (any AnalyticsClient)?
    private let log = AppLog(category: .app)

    public init(reporter: any CrashReporter, analytics: (any AnalyticsClient)? = nil) {
        self.reporter = reporter
        self.analytics = analytics
        super.init()
    }

    /// Registers this subscriber with `MXMetricManager`. Call once at app launch.
    public func register() {
        MXMetricManager.shared.add(self)
    }

    /// Unregisters this subscriber. Call on deinit if needed.
    public func unregister() {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            reporter.addBreadcrumb(CrashBreadcrumb(
                category: "metrickit",
                message: "MetricKit metric payload received (period: \(payload.timeStampBegin)–\(payload.timeStampEnd))",
                level: .info
            ))
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let cpuExceptions = payload.cpuExceptionDiagnostics?.count ?? 0
            let diskWrites = payload.diskWriteExceptionDiagnostics?.count ?? 0

            if crashes > 0 {
                log.error("MetricKit: \(crashes) crash diagnostic(s)")
                analytics?.track(.custom(name: "metrickit_crash", properties: ["count": String(crashes)]))
                reporter.addBreadcrumb(CrashBreadcrumb(
                    category: "metrickit",
                    message: "MetricKit crash diagnostic: \(crashes) crash(es)",
                    level: .critical
                ))
                reporter.captureMessage(
                    "MetricKit crash diagnostic: \(crashes) crash(es)",
                    level: .critical
                )
            }

            if hangs > 0 {
                log.warning("MetricKit: \(hangs) hang diagnostic(s)")
                analytics?.track(.custom(name: "metrickit_hang", properties: ["count": String(hangs)]))
                reporter.addBreadcrumb(CrashBreadcrumb(
                    category: "metrickit",
                    message: "MetricKit hang diagnostic: \(hangs) hang(s)",
                    level: .warning
                ))
                reporter.captureMessage(
                    "MetricKit hang diagnostic: \(hangs) hang(s)",
                    level: .warning
                )
            }

            if cpuExceptions > 0 {
                log.warning("MetricKit: \(cpuExceptions) CPU exception(s)")
                analytics?.track(.custom(name: "metrickit_cpu_exception", properties: ["count": String(cpuExceptions)]))
                reporter.captureMessage(
                    "MetricKit CPU exception: \(cpuExceptions) event(s)",
                    level: .warning
                )
            }

            if diskWrites > 0 {
                analytics?.track(.custom(name: "metrickit_disk_write_exception", properties: ["count": String(diskWrites)]))
                reporter.captureMessage(
                    "MetricKit disk-write exception: \(diskWrites) event(s)",
                    level: .warning
                )
            }
        }
    }
}
#endif
