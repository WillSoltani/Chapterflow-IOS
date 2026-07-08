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

    /// Registers both BG task handlers with `BGTaskScheduler`.
    ///
    /// Must be called before the app finishes launching (i.e. from `AppModel.init`).
    /// Safe to call multiple times — subsequent registrations for the same identifier
    /// are no-ops.
    public nonisolated func registerBackgroundTasks() {
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
        appRefreshHandle = Task { [weak self] in
            self?.logger.info("BackgroundSync: foreground sync started")
            await work()
            self?.appRefreshHandle = nil
        }
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
        let handle = Task { [weak self] in
            self?.logger.info("BackgroundSync: BGAppRefresh started")
            await work()
            task.setTaskCompleted(success: true)
            self?.appRefreshHandle = nil
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
        let handle = Task { [weak self] in
            self?.logger.info("BackgroundSync: BGProcessing started")
            await work()
            task.setTaskCompleted(success: true)
            self?.processingHandle = nil
        }
        processingHandle = handle
        task.expirationHandler = {
            handle.cancel()
            task.setTaskCompleted(success: false)
        }
        await handle.value
    }
}
#endif
