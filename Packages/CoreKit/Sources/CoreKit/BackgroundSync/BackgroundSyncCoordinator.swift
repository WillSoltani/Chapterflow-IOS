#if os(iOS)
import BackgroundTasks
import Foundation
import UIKit
import os

// MARK: - BGTask sendable wrappers

// BGAppRefreshTask and BGProcessingTask are ObjC classes whose mutation points
// (setTaskCompleted, expirationHandler) are thread-safe by design.  Wrapping them
// in a private @unchecked Sendable box lets us cross the actor boundary without
// adding a retroactive conformance that might conflict with AuthKit's own extension.
private final class AppRefreshTaskBox: @unchecked Sendable {
    let task: BGAppRefreshTask
    init(_ task: BGAppRefreshTask) { self.task = task }
}

private final class ProcessingTaskBox: @unchecked Sendable {
    let task: BGProcessingTask
    init(_ task: BGProcessingTask) { self.task = task }
}

// MARK: - BackgroundSyncCoordinator

/// Wires ``SyncEngine`` and ``DownloadManager`` into `BGTaskScheduler`.
///
/// Lives in `CoreKit` so it is independent of feature packages. All actual work
/// is injected as `@Sendable` closures, keeping this class free of LibraryFeature
/// or SyncEngine imports.
///
/// **Lifecycle:**
/// 1. Create in `AppModel.init()`.
/// 2. Call ``registerBackgroundTasks()`` immediately (before the app finishes launching).
/// 3. Call ``scheduleBackgroundTasks()`` each time the scene enters `.background`.
/// 4. Call ``triggerForegroundSync()`` each time the scene becomes `.active`.
///
/// **Work gating:**
/// All work is suppressed when Low Power Mode is active or the user has disabled
/// Background App Refresh for this app.
@MainActor
public final class BackgroundSyncCoordinator {

    // MARK: - BG task identifiers

    /// Identifier for the lightweight BGAppRefresh task: drains the outbox and
    /// refreshes entitlement. Must appear in `BGTaskSchedulerPermittedIdentifiers`.
    nonisolated(unsafe) public static let appRefreshIdentifier = "com.chapterflow.ios.syncRefresh"

    /// Identifier for the heavier BGProcessing task: resumes interrupted downloads
    /// and prefetches the next chapter of in-progress books.
    /// Must appear in `BGTaskSchedulerPermittedIdentifiers`.
    nonisolated(unsafe) public static let processingIdentifier = "com.chapterflow.ios.contentPrefetch"

    // MARK: - Dependencies (closure-injected)

    /// Work performed during a BGAppRefresh cycle: drain outbox + refresh entitlement.
    private let onAppRefreshWork: @Sendable () async -> Void

    /// Work performed during a BGProcessing cycle: resume interrupted downloads and
    /// prefetch next chapters. Only called when Wi-Fi is available (checked internally).
    private let onProcessingWork: @Sendable () async -> Void

    // MARK: - Coalescing handles

    private var appRefreshHandle: Task<Void, Never>?
    private var processingHandle: Task<Void, Never>?
    private var appRefreshOperationID: UUID?
    private var processingOperationID: UUID?

    // MARK: - Logger

    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "BackgroundSync")

    // MARK: - Init

    public init(
        onAppRefreshWork: @escaping @Sendable () async -> Void,
        onProcessingWork: @escaping @Sendable () async -> Void
    ) {
        self.onAppRefreshWork = onAppRefreshWork
        self.onProcessingWork = onProcessingWork
    }

    // MARK: - Registration

    // BGTaskScheduler throws if the same identifier is registered twice.
    // AppModel.init is called on every SwiftUI body evaluation so guard with
    // a static flag (the coordinator instance changes but the scheduler does not).
    nonisolated(unsafe) private static var bgTasksRegistered = false

    /// Registers both BG task handlers with `BGTaskScheduler`.
    ///
    /// Must be called before the app finishes launching (i.e. from `AppModel.init`).
    /// No-op after the first call (BGTaskScheduler throws on duplicate registration).
    public nonisolated func registerBackgroundTasks() {
        guard !Self.bgTasksRegistered else { return }
        Self.bgTasksRegistered = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.appRefreshIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = AppRefreshTaskBox(refreshTask)
            Task { @MainActor [weak self, box] in
                await self?.handleAppRefresh(box.task)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = ProcessingTaskBox(processingTask)
            Task { @MainActor [weak self, box] in
                await self?.handleProcessing(box.task)
            }
        }
    }

    // MARK: - Scheduling

    /// Schedules both BG tasks. Call when the scene enters `.background`.
    public nonisolated func scheduleBackgroundTasks() {
        scheduleAppRefresh()
        scheduleProcessing()
    }

    private nonisolated func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
        // Run no earlier than 15 minutes from now.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Non-fatal: the system refuses the request when background refresh is
            // disabled by the user or the app hasn't been used recently enough.
        }
    }

    private nonisolated func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresNetworkConnectivity = true
        // Allow running on battery; system will opportunistically prefer charging.
        request.requiresExternalPower = false
        // Run no earlier than 30 minutes from now.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Non-fatal.
        }
    }

    // MARK: - Foreground trigger

    /// Triggers a lightweight app-refresh cycle immediately.
    ///
    /// Call when `scenePhase` transitions to `.active`. Coalesces with any in-flight
    /// BG-refresh work: if a BGAppRefresh cycle is already running it is cancelled
    /// and a fresh pass starts.
    public func triggerForegroundSync() {
        guard isWorkPermitted else {
            logger.debug("BackgroundSync: skipping foreground sync (LPM or BG refresh denied)")
            return
        }
        let work = onAppRefreshWork
        appRefreshHandle?.cancel()
        let operationID = UUID()
        appRefreshOperationID = operationID
        appRefreshHandle = Task { [weak self] in
            self?.logger.info("BackgroundSync: foreground sync started")
            await work()
            self?.finishAppRefresh(operationID: operationID)
        }
    }

    /// Cancels and joins every retained background-work task.
    ///
    /// This is the account-lifetime teardown boundary. Both handles are detached
    /// before suspension so a re-entrant call cannot mistake old work for a new
    /// account's task, and repeated calls are harmless.
    public func cancelActiveWork() async {
        let appRefresh = appRefreshHandle
        let processing = processingHandle
        appRefreshHandle = nil
        processingHandle = nil
        appRefreshOperationID = nil
        processingOperationID = nil

        appRefresh?.cancel()
        processing?.cancel()
        await appRefresh?.value
        await processing?.value
    }

    // MARK: - Work-permission gate

    /// `false` when Low Power Mode is active or the user has disabled Background App
    /// Refresh for this app. Both conditions warrant skipping all proactive network work.
    private var isWorkPermitted: Bool {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        return UIApplication.shared.backgroundRefreshStatus != .denied
    }

    // MARK: - BGAppRefresh handler

    private func handleAppRefresh(_ task: BGAppRefreshTask) async {
        // Re-schedule immediately so the chain stays alive regardless of outcome.
        scheduleAppRefresh()

        guard isWorkPermitted else {
            logger.info("BackgroundSync: skipping BGAppRefresh (not permitted)")
            task.setTaskCompleted(success: true)
            return
        }

        appRefreshHandle?.cancel()
        let work = onAppRefreshWork
        let operationID = UUID()
        appRefreshOperationID = operationID
        let handle = Task { [weak self] in
            self?.logger.info("BackgroundSync: BGAppRefresh started")
            await work()
            task.setTaskCompleted(success: true)
            self?.finishAppRefresh(operationID: operationID)
        }
        appRefreshHandle = handle
        task.expirationHandler = {
            handle.cancel()
            task.setTaskCompleted(success: false)
        }
        await handle.value
    }

    // MARK: - BGProcessing handler

    private func handleProcessing(_ task: BGProcessingTask) async {
        // Re-schedule immediately.
        scheduleProcessing()

        guard isWorkPermitted else {
            logger.info("BackgroundSync: skipping BGProcessing (not permitted)")
            task.setTaskCompleted(success: true)
            return
        }

        processingHandle?.cancel()
        let work = onProcessingWork
        let operationID = UUID()
        processingOperationID = operationID
        let handle = Task { [weak self] in
            self?.logger.info("BackgroundSync: BGProcessing started")
            await work()
            task.setTaskCompleted(success: true)
            self?.finishProcessing(operationID: operationID)
        }
        processingHandle = handle
        task.expirationHandler = {
            handle.cancel()
            task.setTaskCompleted(success: false)
        }
        await handle.value
    }

    private func finishAppRefresh(operationID: UUID) {
        guard appRefreshOperationID == operationID else { return }
        appRefreshOperationID = nil
        appRefreshHandle = nil
    }

    private func finishProcessing(operationID: UUID) {
        guard processingOperationID == operationID else { return }
        processingOperationID = nil
        processingHandle = nil
    }

    #if DEBUG
    /// Starts both work classes without BGTaskScheduler so cancellation is deterministic in tests.
    func startActiveWorkForTesting() {
        appRefreshHandle?.cancel()
        processingHandle?.cancel()

        let refreshID = UUID()
        appRefreshOperationID = refreshID
        let refreshWork = onAppRefreshWork
        appRefreshHandle = Task { [weak self] in
            await refreshWork()
            self?.finishAppRefresh(operationID: refreshID)
        }

        let processingID = UUID()
        processingOperationID = processingID
        let processingWork = onProcessingWork
        processingHandle = Task { [weak self] in
            await processingWork()
            self?.finishProcessing(operationID: processingID)
        }
    }

    var activeWorkCountForTesting: Int {
        (appRefreshHandle == nil ? 0 : 1) + (processingHandle == nil ? 0 : 1)
    }
    #endif
}
#endif
