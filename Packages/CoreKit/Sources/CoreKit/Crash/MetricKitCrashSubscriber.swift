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
    private let log = AppLog(category: .app)

    public init(reporter: any CrashReporter) {
        self.reporter = reporter
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
                reporter.captureMessage(
                    "MetricKit CPU exception: \(cpuExceptions) event(s)",
                    level: .warning
                )
            }

            if diskWrites > 0 {
                reporter.captureMessage(
                    "MetricKit disk-write exception: \(diskWrites) event(s)",
                    level: .warning
                )
            }
        }
    }
}
#endif
