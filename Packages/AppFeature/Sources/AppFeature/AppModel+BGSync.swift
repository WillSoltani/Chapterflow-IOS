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
        fileStore: FileStore,
        apiClient: any APIClientProtocol
    ) -> DownloadManager {
        DownloadManager(
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
        engine: SyncEngine,
        downloadManager: DownloadManager,
        entitlementService: EntitlementService
    ) -> BackgroundSyncCoordinator {
        BackgroundSyncCoordinator(
            onAppRefreshWork: { @Sendable [box, engine, entitlementService] in
                guard let uid = box.userId else { return }
                await engine.drainAndWait(userId: uid)
                await entitlementService.refresh()
            },
            onProcessingWork: { @Sendable [box, downloadManager] in
                guard let uid = box.userId else { return }
                await downloadManager.resumeInterruptedDownloads(userId: uid)
                if !Task.isCancelled {
                    await downloadManager.prefetchNextChapters(userId: uid)
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
