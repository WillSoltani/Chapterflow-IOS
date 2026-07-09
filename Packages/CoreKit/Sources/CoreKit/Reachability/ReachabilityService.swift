import Foundation
import Network

/// Centralized network reachability service.
///
/// Wraps `NWPathMonitor` so all features share a single path observer instead
/// of each spinning up their own. Repositories use ``isConnectedSync`` for
/// in-actor synchronous checks; SwiftUI views observe ``isConnected`` on the
/// main actor.
///
/// Usage from a `@MainActor` view or model:
/// ```swift
/// @Environment(ReachabilityService.self) var reachability
/// if !reachability.isConnected { OfflineBannerView() }
/// ```
///
/// Usage inside an actor-isolated repository:
/// ```swift
/// guard reachability.isConnectedSync else { throw AppError.offline }
/// ```
@Observable
public final class ReachabilityService: @unchecked Sendable {

    // MARK: - Main-actor observable state

    /// Whether the device currently has a usable network path.
    /// Observed on the main actor for SwiftUI views and `@Observable` models.
    @MainActor public private(set) var isConnected: Bool = true

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.chapterflow.reachability", qos: .utility)

    // MARK: - Init / teardown

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Synchronous check (actor-safe)

    /// Whether the device has a usable network path, checked synchronously
    /// against the monitor's current path.
    ///
    /// Use this inside actors or other non-`@MainActor` contexts where
    /// awaiting the main-actor `isConnected` would be too expensive. The result
    /// is a point-in-time snapshot and may lag behind `isConnected` by one
    /// path-update cycle (~100 ms maximum).
    public nonisolated var isConnectedSync: Bool {
        // In UITest stub mode every request is intercepted by CFStubURLProtocol, so
        // the real network path is irrelevant. Skip the monitor check to avoid a race
        // where NWPathMonitor hasn't fired its first callback yet and reports .unsatisfied,
        // which would make repositories throw AppError.offline before any request is made.
        #if DEBUG
        if ProcessInfo.processInfo.environment["CF_STUB_SERVER"] == "1" { return true }
        #endif
        return monitor.currentPath.status == .satisfied
    }
}
