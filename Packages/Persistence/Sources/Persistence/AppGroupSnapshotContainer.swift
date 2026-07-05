import Foundation
import SwiftData

/// Factory for the App Group *snapshot* `ModelContainer`.
///
/// This is an entirely **separate** container from ``PersistenceController``'s
/// main store (`ChapterFlow.store`). It holds only ``AppGroupContinueRecord`` —
/// the lightweight continue-reading row that widgets and extensions can read.
///
/// Because it is separate it never participates in ``PersistenceMigrationPlan``
/// and its schema can evolve independently (RF4).
///
/// ### Extension access
/// Extensions **may** open this container read-only. Because the main app
/// (``SharedStateWriter``) is the sole writer and always uses a single context,
/// the risk of SQLite corruption from concurrent access is very low. Extensions
/// should nonetheless avoid writing to this store.
///
/// ### Usage
/// ```swift
/// // App startup (AppFeature):
/// let container = try AppGroupSnapshotContainer.make()
/// await SharedStateWriter.shared.configure(snapshotContainer: container)
///
/// // Widget/extension:
/// let container = try AppGroupSnapshotContainer.make()
/// let context = ModelContext(container)
/// let records = try context.fetch(FetchDescriptor<AppGroupContinueRecord>())
/// ```
public enum AppGroupSnapshotContainer {
    /// SQLite file name inside the App Group container.
    /// Deliberately different from `ChapterFlow.store` (the main Persistence store).
    public static let storeFileName = "AppGroupSnapshot.store"

    /// Builds and returns a `ModelContainer` for the App Group snapshot store.
    ///
    /// - Parameter inMemory: `true` for an ephemeral in-memory store (tests/previews).
    /// - Throws: ``PersistenceError/appGroupUnavailable`` when the App Group
    ///   container directory cannot be resolved (missing entitlement).
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([AppGroupContinueRecord.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            guard let dir = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            else {
                throw PersistenceError.appGroupUnavailable
            }
            let url = dir.appending(path: storeFileName)
            config = ModelConfiguration(schema: schema, url: url)
        }
        return try ModelContainer(for: schema, configurations: config)
    }
}
