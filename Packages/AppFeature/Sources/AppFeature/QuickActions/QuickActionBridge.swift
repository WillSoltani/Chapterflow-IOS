#if canImport(UIKit)
/// Relays `UIApplicationShortcutItem` taps from `AppDelegate` into `AppModel`.
///
/// `AppDelegate.application(_:performActionFor:completionHandler:)` writes the
/// shortcut type; `AppModel.consumeQuickAction()` reads and clears it on the
/// next foreground activation. The same bridge handles cold-launch shortcuts
/// (set in `didFinishLaunchingWithOptions`).
///
/// Thread-safety: both writer (main-thread UIApplicationDelegate) and reader
/// (@MainActor AppModel) are on the main thread, so `@unchecked Sendable` is safe.
public final class QuickActionBridge: @unchecked Sendable {
    public static let shared = QuickActionBridge()
    private init() {}

    /// The `UIApplicationShortcutItem.type` string from the most-recent tap.
    /// Cleared by `AppModel.consumeQuickAction()` after routing.
    var pendingShortcutType: String?
}

// MARK: - Shortcut type constants

extension QuickActionBridge {
    enum ShortcutType {
        static let continueReading = "com.chapterflow.ios.continue-reading"
        static let reviews         = "com.chapterflow.ios.reviews"
        static let ask             = "com.chapterflow.ios.ask"
    }
}
#endif
