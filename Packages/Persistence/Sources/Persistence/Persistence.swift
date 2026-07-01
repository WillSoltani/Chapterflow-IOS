import Foundation

/// Umbrella namespace for the Persistence module.
///
/// The module provides the app's local storage stack:
/// - ``PersistenceController`` — the SwiftData `ModelContainer` factory with a
///   configurable schema, main + background contexts, and a migration-plan scaffold.
/// - ``TokenStore`` — a Keychain-backed struct for the Cognito token triple.
/// - ``AppPreferences`` — an `@Observable` store of user reading/audio preferences
///   backed by App-Group `UserDefaults`.
/// - ``KeyValueStore`` and ``FileStore`` — small wrappers for lightweight values and
///   downloaded audio/content blobs.
public enum Persistence {
    /// The name of this module. Useful as a smoke-test symbol.
    public static let moduleName = "Persistence"
}

/// Shared App Group identifier used by the SwiftData store, preferences, and the
/// Keychain access group so widgets and extensions read the same data.
public enum AppGroup {
    /// The App Group container identifier (must match the app + widget entitlements).
    public static let identifier = "group.com.chapterflow"
}

/// Errors thrown by the Persistence layer.
public enum PersistenceError: Error, Equatable, Sendable {
    /// The App Group container could not be resolved (missing entitlement / sandbox).
    case appGroupUnavailable
    /// A Keychain operation failed with the given `OSStatus`.
    case keychain(OSStatus)
    /// A requested file or record was not found.
    case notFound
}
