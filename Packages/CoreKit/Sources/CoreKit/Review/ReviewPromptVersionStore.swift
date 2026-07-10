import Foundation

/// Persists the app version at which a review was last requested.
///
/// This is the only piece of state the review machinery keeps. It is modelled as a
/// protocol so ``ReviewPromptController`` stays testable with an in-memory fake, and so
/// the concrete implementation can be backed by the app's existing key-value/preferences
/// store rather than introducing a new singleton.
public protocol ReviewPromptVersionStore: Sendable {
    /// The app version at which a review was last requested, or `nil` if never.
    func lastPromptedVersion() -> String?

    /// Records `version` as the version at which a review was most recently requested.
    func setLastPromptedVersion(_ version: String)
}

/// A simple in-memory ``ReviewPromptVersionStore`` for tests and previews.
public final class InMemoryReviewPromptVersionStore: ReviewPromptVersionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedVersion: String?

    public init(lastPromptedVersion: String? = nil) {
        self.storedVersion = lastPromptedVersion
    }

    public func lastPromptedVersion() -> String? {
        lock.lock(); defer { lock.unlock() }
        return storedVersion
    }

    public func setLastPromptedVersion(_ version: String) {
        lock.lock(); defer { lock.unlock() }
        storedVersion = version
    }
}
