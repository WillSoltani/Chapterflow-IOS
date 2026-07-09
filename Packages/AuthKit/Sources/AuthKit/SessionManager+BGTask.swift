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

    // BGTaskScheduler throws if the same identifier is registered twice.
    // AppModel.init is called on every SwiftUI body evaluation (the @State
    // initialValue is discarded after the first), so guard with a static flag.
    nonisolated(unsafe) private static var bgRefreshRegistered = false

    /// Registers the background app-refresh handler with `BGTaskScheduler`.
    ///
    /// Call once at app launch. BGTaskScheduler throws an NSException if the
    /// same identifier is registered twice, so this method is a no-op after
    /// the first call.
    public nonisolated func registerBackgroundRefresh() {
        guard !Self.bgRefreshRegistered else { return }
        Self.bgRefreshRegistered = true
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
