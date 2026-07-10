import Foundation
import Persistence

// MARK: - WhatsNewStore

/// Persists the last app version for which the user has seen the What's New
/// screen, so it never re-shows for the same version.
///
/// Backed by the existing ``KeyValueStore`` (App Group `UserDefaults`) — no new
/// singleton. Construct one wherever it's needed; it holds no mutable state of
/// its own.
public struct WhatsNewStore {
    private let store: KeyValueStore
    private let key = "whatsNew.lastSeenVersion"

    /// - Parameter store: The backing key-value store. Defaults to the App Group
    ///   suite; pass an isolated store in tests/previews.
    public init(store: KeyValueStore = KeyValueStore()) {
        self.store = store
    }

    /// The last version the user saw What's New for, or `nil` if never recorded.
    public var lastSeenVersion: String? {
        store.value(String.self, forKey: key)
    }

    /// Records `version` as seen so What's New won't auto-present for it again.
    public func markSeen(_ version: String) {
        try? store.set(version, forKey: key)
    }
}
