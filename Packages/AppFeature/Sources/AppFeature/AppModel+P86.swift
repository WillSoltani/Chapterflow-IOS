import Foundation
import CoreKit
import Persistence

// MARK: - P8.6: Quick Actions + Focus Filter

extension AppModel {

    // MARK: - Quick Actions

    /// Reads a pending Home-screen quick action tap written by `AppDelegate`
    /// via `QuickActionBridge` and routes it to the correct tab.
    ///
    /// Call when the app becomes active (scenePhase → `.active`) so cold-launch
    /// and foreground quick-action taps are both handled on first activation.
    public func consumeQuickAction() {
        #if canImport(UIKit)
        guard let type = QuickActionBridge.shared.pendingShortcutType else { return }
        QuickActionBridge.shared.pendingShortcutType = nil
        switch type {
        case QuickActionBridge.ShortcutType.continueReading:
            // The legacy App Group continue-reading snapshot has no account
            // owner. Preserve it for WP-ID-01B and open only the neutral library.
            handle(deepLink: .library)
        case QuickActionBridge.ShortcutType.reviews:
            handle(deepLink: .review)
        case QuickActionBridge.ShortcutType.ask:
            handle(deepLink: .engagement)
        default:
            break
        }
        #endif
    }

    // MARK: - Focus Filter

    /// Reads the Reading Focus filter state written by `ReadingFocusFilter.perform()`
    /// and updates `isReadingFocusActive`.
    ///
    /// Call when the app becomes active so the UI reflects the current Focus state.
    public func consumeFocusFilter() {
        let isActive = UserDefaults(suiteName: AppGroup.identifier)?
            .bool(forKey: FocusFilterKeys.isReadingFocusActive) ?? false
        isReadingFocusActive = isActive
    }
}
