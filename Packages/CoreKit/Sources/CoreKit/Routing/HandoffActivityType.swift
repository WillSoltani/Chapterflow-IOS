import Foundation

/// Activity-type string constants for `NSUserActivity` Handoff integration.
///
/// Register `HandoffActivityType.reading` under `NSUserActivityTypes` in the
/// app's `Info.plist` so iOS recognises incoming activities from other devices.
public enum HandoffActivityType {
    /// Advertises an active in-app reading session for Continuity Handoff.
    ///
    /// Advertised from ``ReadingFlowView`` via SwiftUI's `.userActivity(_:isActive:_:)`
    /// modifier; resumed by ``AppRootView`` via `.onContinueUserActivity(_:)`.
    ///
    /// The activity's `webpageURL` is set to the Universal Link equivalent so that
    /// non-iOS devices (e.g. a Mac without the app) can continue in Safari.
    public static let reading = "com.chapterflow.ios.reading"
}

/// Keys stored in the `NSUserActivity.userInfo` dictionary for reading Handoff.
public enum HandoffKeys {
    /// The book identifier (`String`).
    public static let bookId = "bookId"
    /// The one-based chapter number (`Int`).
    public static let chapterNumber = "chapterNumber"
    /// The `VariantFamily.rawValue` (`String`) — defaults to `"EMH"` if absent.
    public static let variantFamily = "variantFamily"
}
