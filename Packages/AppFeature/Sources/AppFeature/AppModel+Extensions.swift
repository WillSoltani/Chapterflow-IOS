import Foundation
import OSLog
import Persistence

private let log = Logger(subsystem: "com.chapterflow", category: "extensions")

// MARK: - Extension outbox pickup

extension AppModel {

    /// Preserves the legacy ownerless extension outbox for WP-ID-01B attribution.
    ///
    /// Call when `scenePhase` transitions to `.active`.
    ///
    /// 01A must not guess that an ownerless item belongs to the active account and
    /// must not clear it as though import succeeded.
    public func drainExtensionOutbox() {
        let outbox = ExtensionOutbox()
        let items = outbox.readAll()
        guard !items.isEmpty else { return }
        log.notice("Extension outbox contains ownerless legacy items; preserving for account attribution")
        extensionInboxCount = 0
        showExtensionInboxBanner = false
    }
}
