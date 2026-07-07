import Foundation

/// Thread-safe container for the current authenticated user ID.
///
/// Written on the `@MainActor` (via ``AppModel/hydrateDisplayName()`` and
/// ``AppModel/signOut()``); read cross-actor by repository closures.
/// `@unchecked Sendable` because reads/writes are guarded by `NSLock`.
final class UserIdBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _userId: String?

    var userId: String? {
        get { lock.withLock { _userId } }
        set { lock.withLock { _userId = newValue } }
    }

    init(userId: String? = nil) {
        _userId = userId
    }
}
