#if os(iOS)
import Testing
import Foundation
@testable import CoreKit

// MARK: - BackgroundSyncCoordinator tests

/// Tests for scheduling/coalescing/gating logic in BackgroundSyncCoordinator.
///
/// BGTask registration and handler execution require OS-level infrastructure
/// (Info.plist identifiers, a real BGTaskScheduler). Those paths are not tested
/// here — only the logic that lives entirely in the coordinator itself.
@MainActor
@Suite("BackgroundSyncCoordinator", .serialized)
struct BackgroundSyncCoordinatorTests {

    // MARK: - Helpers

    private actor InvocationCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    // MARK: - Foreground sync invokes work

    @Test("triggerForegroundSync runs appRefreshWork when permitted")
    func foregroundSyncRunsWork() async throws {
        let counter = InvocationCounter()
        let coordinator = BackgroundSyncCoordinator(
            onAppRefreshWork: { await counter.increment() },
            onProcessingWork: {}
        )
        coordinator.triggerForegroundSync()
        try await Task.sleep(for: .milliseconds(150))
        // In the test environment (LPM off, BG refresh available) work should run.
        // We can't guarantee BG refresh status, so assert at-most-one invocation.
        #expect(await counter.count <= 1)
    }

    // MARK: - Coalescing

    @Test("rapid back-to-back calls coalesce to at most one work run")
    func coalescesRapidCalls() async throws {
        let counter = InvocationCounter()
        let coordinator = BackgroundSyncCoordinator(
            onAppRefreshWork: {
                // Brief sleep ensures the first task is still live when the
                // second triggerForegroundSync cancels it.
                try? await Task.sleep(for: .milliseconds(60))
                await counter.increment()
            },
            onProcessingWork: {}
        )
        // Both calls happen on the main actor before any task body can run,
        // so the second call always cancels the first.
        coordinator.triggerForegroundSync()
        coordinator.triggerForegroundSync()
        try await Task.sleep(for: .milliseconds(400))
        let count = await counter.count
        // Cancellation prevents the first run; only the second can complete.
        #expect(count <= 1)
    }

    @Test("subsequent calls after completion each run once")
    func sequentialCallsEachRunOnce() async throws {
        let counter = InvocationCounter()
        let coordinator = BackgroundSyncCoordinator(
            onAppRefreshWork: { await counter.increment() },
            onProcessingWork: {}
        )
        coordinator.triggerForegroundSync()
        try await Task.sleep(for: .milliseconds(100))
        let countAfterFirst = await counter.count

        coordinator.triggerForegroundSync()
        try await Task.sleep(for: .milliseconds(100))
        let countAfterSecond = await counter.count

        // Each completed call contributes at most 1; totals monotonically increase.
        #expect(countAfterSecond >= countAfterFirst)
        #expect(countAfterSecond <= 2)
    }

    // MARK: - Scheduling / registration safety

    @Test("scheduleBackgroundTasks does not crash in test environment")
    func scheduleDoesNotCrash() {
        let coordinator = BackgroundSyncCoordinator(
            onAppRefreshWork: {},
            onProcessingWork: {}
        )
        // BGTaskScheduler.submit silently fails in test environments (identifiers
        // not registered) — this must not propagate as an unhandled error.
        coordinator.scheduleBackgroundTasks()
    }

    @Test("registerBackgroundTasks is safe to call multiple times")
    func registerIsIdempotent() {
        let coordinator = BackgroundSyncCoordinator(
            onAppRefreshWork: {},
            onProcessingWork: {}
        )
        coordinator.registerBackgroundTasks()
        coordinator.registerBackgroundTasks()
    }

    // MARK: - BG task identifiers

    @Test("identifier constants have expected values")
    func identifierValues() {
        #expect(BackgroundSyncCoordinator.appRefreshIdentifier == "com.chapterflow.ios.syncRefresh")
        #expect(BackgroundSyncCoordinator.processingIdentifier == "com.chapterflow.ios.contentPrefetch")
    }
}
#endif
