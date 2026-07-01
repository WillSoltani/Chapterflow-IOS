#if os(iOS)
import Foundation
import BackgroundTasks

// BGAppRefreshTask is an ObjC class designed for cross-thread use; the
// @unchecked Sendable conformance is safe here.
extension BGAppRefreshTask: @unchecked Sendable {}

extension SessionManager {

    /// The `BGTaskScheduler` identifier for proactive token refresh.
    ///
    /// This value must be listed in the app target's `Info.plist` under the
    /// `BGTaskSchedulerPermittedIdentifiers` key before the scheduler will
    /// honour the registration.
    public nonisolated static let bgRefreshIdentifier = "com.chapterflow.ios.tokenRefresh"

    /// Registers the background app-refresh handler with `BGTaskScheduler`.
    ///
    /// Call once at app launch. Safe to call multiple times — subsequent
    /// registrations for the same identifier are no-ops in the OS.
    public nonisolated func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgRefreshIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                self?.handleBackgroundRefresh(refreshTask)
            }
        }
    }

    /// Schedules a background app-refresh task to run no earlier than `earliest`.
    ///
    /// Call when the app enters the background (observe `ScenePhase.background`).
    /// The default `earliest` is 1 hour from now to stay ahead of Cognito's
    /// default 1-hour id_token expiry.
    public nonisolated func scheduleBackgroundRefresh(
        earliest: Date = Date(timeIntervalSinceNow: 3600)
    ) {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgRefreshIdentifier)
        request.earliestBeginDate = earliest
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Private

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        // Reschedule immediately so we don't miss the next window.
        scheduleBackgroundRefresh()

        let work = Task {
            do {
                try await self.refresh()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
#endif
