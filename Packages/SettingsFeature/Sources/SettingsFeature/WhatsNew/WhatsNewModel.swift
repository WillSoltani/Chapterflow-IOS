import Foundation
import Observation

// MARK: - WhatsNewModel

/// Coordinates What's New: which release to show, whether to auto-present at
/// launch, and recording the last-seen version.
///
/// UI state lives here (`@MainActor @Observable`); the underlying decisions are
/// delegated to the pure ``WhatsNewPolicy`` and the value-type
/// ``WhatsNewContentProvider`` / ``WhatsNewStore`` so they stay unit-testable.
@MainActor
@Observable
public final class WhatsNewModel {

    /// The running app's marketing version.
    public let currentVersion: String

    @ObservationIgnored private let provider: WhatsNewContentProvider
    @ObservationIgnored private let store: WhatsNewStore

    /// - Parameters:
    ///   - currentVersion: The running app version. Defaults to the main
    ///     bundle's `CFBundleShortVersionString`.
    ///   - provider: Bundled content source.
    ///   - store: Last-seen-version persistence.
    public init(
        currentVersion: String = WhatsNewModel.bundleShortVersion(),
        provider: WhatsNewContentProvider = WhatsNewContentProvider(),
        store: WhatsNewStore = WhatsNewStore()
    ) {
        self.currentVersion = currentVersion
        self.provider = provider
        self.store = store
    }

    /// The release matching the current version, if any.
    public var currentRelease: WhatsNewRelease? {
        provider.release(forVersion: currentVersion)
    }

    /// The release to render on screen — the current release when available,
    /// otherwise the newest bundled release, so the always-available Settings
    /// entry always has something to show.
    public var displayRelease: WhatsNewRelease? {
        currentRelease ?? provider.releases.max { AppVersion($0.version) < AppVersion($1.version) }
    }

    /// Whether What's New should auto-present at launch: only after an update
    /// (per ``WhatsNewPolicy``) and only when there is content to show.
    public var shouldPresentOnLaunch: Bool {
        guard currentRelease != nil else { return false }
        return WhatsNewPolicy.shouldShow(
            lastSeenVersion: store.lastSeenVersion,
            currentVersion: currentVersion
        )
    }

    /// Records the current version as seen so What's New won't re-present for it.
    public func markCurrentVersionSeen() {
        store.markSeen(currentVersion)
    }

    /// Reads `CFBundleShortVersionString` from the main bundle.
    public static func bundleShortVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
