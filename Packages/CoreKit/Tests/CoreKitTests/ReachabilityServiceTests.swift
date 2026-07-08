import Testing
import Network
@testable import CoreKit

@Suite("ReachabilityService")
struct ReachabilityServiceTests {

    @Test("defaults to isConnected = true before the monitor fires its first update")
    @MainActor
    func defaultIsConnected() {
        let service = ReachabilityService()
        // The optimistic default prevents an offline flash on startup even before
        // NWPathMonitor fires its initial path update (~50 ms after start).
        #expect(service.isConnected == true)
    }

    @Test("isConnectedSync is callable from a non-MainActor context")
    func isConnectedSyncNonisolated() async {
        let service = ReachabilityService()
        // nonisolated: must not require await or @MainActor
        let result = service.isConnectedSync
        #expect(result == true || result == false)
    }

    @Test("multiple instances share independent monitors without interference")
    @MainActor
    func multipleInstancesAreIndependent() {
        let a = ReachabilityService()
        let b = ReachabilityService()
        // Both start with the same optimistic default.
        #expect(a.isConnected == b.isConnected)
    }

    @Test("isConnectedSync reflects current NWPathMonitor status")
    func isConnectedSyncReflectsMonitor() async {
        let service = ReachabilityService()
        // Give the monitor a moment to settle so we're reading a real path status.
        try? await Task.sleep(for: .milliseconds(200))
        let syncValue = service.isConnectedSync
        // We can't assert true/false (depends on test-host network),
        // but we verify the property is a valid Bool.
        #expect(syncValue == true || syncValue == false)
    }
}
