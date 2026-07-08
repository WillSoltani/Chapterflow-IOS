import AppIntents
import CoreKit
import Foundation
import Persistence

// MARK: - ReadingFocusFilter

/// "Reading Focus" system filter — surfaces only reading content and suppresses
/// social features while a compatible Focus mode is active on the device.
///
/// Configure from: Settings → Focus → [Any Focus] → Add Filter → ChapterFlow.
/// The system calls `perform()` when the Focus activates or deactivates.
/// The main app reads the stored state via `AppModel.consumeFocusFilter()` on
/// each foreground activation.
public struct ReadingFocusFilter: SetFocusFilterIntent {
    public static let title: LocalizedStringResource = "Reading Focus"
    public static let description = IntentDescription(
        "Filters ChapterFlow to show only reading content and suppresses social features while this Focus is active."
    )

    /// When `true`, the social (Profile) tab is replaced with a reading-only view
    /// and the notification badge is hidden. When `nil` the Focus is deactivating.
    @Parameter(title: "Suppress Social Features")
    public var suppressSocial: Bool?

    public init() {}

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Reading Focus")
    }

    public func perform() async throws -> some IntentResult {
        let isActive = suppressSocial ?? false
        UserDefaults(suiteName: AppGroup.identifier)?
            .set(isActive, forKey: FocusFilterKeys.isReadingFocusActive)
        return .result()
    }
}

// MARK: - FocusFilterKeys

/// UserDefaults key namespace for Focus filter state stored in the App Group.
public enum FocusFilterKeys {
    public static let isReadingFocusActive = "focusFilter.isReadingFocusActive"
}
