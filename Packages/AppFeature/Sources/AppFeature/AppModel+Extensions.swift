import Foundation
import OSLog
import Persistence

private let log = Logger(subsystem: "com.chapterflow", category: "extensions")

// MARK: - Extension outbox pickup

extension AppModel {

    /// Drains the App Group extension outbox and shows a confirmation banner when
    /// the Share or Action extension has saved items since the last foreground cycle.
    ///
    /// Call when `scenePhase` transitions to `.active`.
    ///
    /// **RF4**: Only App Group `UserDefaults` is accessed here — the main SwiftData
    /// store is not opened. Items are stored by the extension and read here.
    public func drainExtensionOutbox() {
        let outbox = ExtensionOutbox()
        let items = outbox.readAll()
        guard !items.isEmpty else { return }

        log.info("Extension outbox: draining \(items.count) item(s)")
        outbox.clear()

        extensionInboxCount = items.count
        showExtensionInboxBanner = true
    }
}
