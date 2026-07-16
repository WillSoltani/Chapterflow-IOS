import Foundation
import CoreKit

// MARK: - BGSync factory helpers + foreground/background hooks

extension AppModel {

    // MARK: - Factory: BackgroundSyncCoordinator

    #if os(iOS)
    static func makeCoordinator(
        broker: SessionBackgroundWorkBroker
    ) -> BackgroundSyncCoordinator {
        BackgroundSyncCoordinator(
            onAppRefreshWork: { @Sendable [broker] in
                await broker.runRefresh()
            },
            onProcessingWork: { @Sendable [broker] in
                await broker.runProcessing()
            }
        )
    }
    #endif

    // MARK: - Background task hooks

    /// Triggers a foreground sync cycle: drains the outbox and refreshes entitlement.
    /// Call when `scenePhase` transitions to `.active`.
    public func triggerForegroundSync() {
        #if os(iOS)
        bgSyncCoordinator.triggerForegroundSync()
        #endif
    }

    /// Schedules BGAppRefresh and BGProcessing tasks for the next background window.
    /// Call when `scenePhase` transitions to `.background`.
    public func scheduleBackgroundTasks() {
        #if os(iOS)
        bgSyncCoordinator.scheduleBackgroundTasks()
        session.scheduleBackgroundRefresh()
        #endif
    }

    // MARK: - Debug launch arguments

    #if DEBUG
    func applyLaunchArguments() {
        guard let arg = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--demo-tab=") }) else { return }
        let name = String(arg.dropFirst("--demo-tab=".count))
        selectedTab = AppTab.allCases.first { $0.title.lowercased() == name.lowercased() } ?? .home
    }
    #endif
}
