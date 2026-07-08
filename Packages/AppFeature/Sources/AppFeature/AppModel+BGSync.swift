import Foundation
import SwiftData
import CoreKit
import Networking
import Persistence
import LibraryFeature
import PaywallFeature
import SyncEngine

// MARK: - BGSync factory helpers + foreground/background hooks

extension AppModel {

    // MARK: - Factory: DownloadManager

    static func makeDownloadManager(
        container: ModelContainer,
        apiClient: any APIClientProtocol
    ) -> DownloadManager? {
        let fileStore = (try? FileStore.applicationSupport(subdirectory: "Downloads"))
            ?? (try? FileStore.applicationSupport())
        guard let fileStore else { return nil }
        return DownloadManager(
            container: container,
            fileStore: fileStore,
            apiClient: apiClient,
            preferences: AppPreferences()
        )
    }

    // MARK: - Factory: BackgroundSyncCoordinator

    #if os(iOS)
    static func makeCoordinator(
        box: UserIdBox,
        engine: SyncEngine?,
        dlManager: DownloadManager?,
        entSvc: EntitlementService
    ) -> BackgroundSyncCoordinator {
        BackgroundSyncCoordinator(
            onAppRefreshWork: { @Sendable [box, engine, entSvc] in
                guard let uid = box.userId else { return }
                await engine?.drainAndWait(userId: uid)
                await entSvc.refresh()
            },
            onProcessingWork: { @Sendable [box, dlManager] in
                guard let uid = box.userId, let manager = dlManager else { return }
                await manager.resumeInterruptedDownloads(userId: uid)
                if !Task.isCancelled {
                    await manager.prefetchNextChapters(userId: uid)
                }
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
