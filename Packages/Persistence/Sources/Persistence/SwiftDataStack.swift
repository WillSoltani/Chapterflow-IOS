import Foundation
import SwiftData

// MARK: - Sample model

/// A small, general-purpose cached key/value record.
///
/// It doubles as the package's **sample `@Model`** used to boot the container in
/// tests, and as a genuinely useful offline cache primitive that features can reuse.
@Model
public final class CachedKeyValue {
    /// Unique lookup key.
    @Attribute(.unique) public var key: String
    /// The stored value (typically JSON or a small string blob).
    public var value: String
    /// When the record was last written; used for read-through cache freshness.
    public var updatedAt: Date

    public init(key: String, value: String, updatedAt: Date = Date()) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

// MARK: - Schema & migration scaffold

/// The current versioned schema. Features add their `@Model` types here (or pass a
/// custom model list to ``PersistenceController``) as the app grows.
public enum PersistenceSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CachedKeyValue.self]
    }
}

/// Migration plan scaffold. New versioned schemas and lightweight/custom
/// ``MigrationStage``s are appended here as the model set evolves.
public enum PersistenceMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [PersistenceSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        // No migrations yet — v1 is the initial schema.
        []
    }
}

// MARK: - Controller

/// Where the SwiftData store is physically located.
public enum StorageMode: Sendable {
    /// The shared App Group container, so widgets/extensions can read the store.
    case appGroup
    /// An ephemeral in-memory store (tests, previews).
    case inMemory
    /// A caller-provided on-disk store URL.
    case privateStore(URL)
}

/// Owns the app's `ModelContainer` and vends main + background contexts.
///
/// The schema is configurable: pass the `@Model` types the app needs (defaults to
/// ``PersistenceSchemaV1``). The store lives in the App Group container so widgets
/// share it. `ModelContainer` is `Sendable`, so this controller is safe to pass across
/// isolation domains; `ModelContext` is not, so background work uses ``BackgroundStore``.
public struct PersistenceController: Sendable {
    /// The underlying SwiftData container.
    public let container: ModelContainer

    /// The main-actor context for UI-driven reads/writes.
    @MainActor public var mainContext: ModelContext { container.mainContext }

    /// Builds a controller for the given models and storage location.
    /// - Parameters:
    ///   - models: The `@Model` types to register. Defaults to the core schema.
    ///   - storage: Where the store lives. Defaults to the App Group container.
    ///   - migrationPlan: Optional migration plan; pass `PersistenceMigrationPlan.self`
    ///     when the model set matches the versioned schema.
    public init(
        models: [any PersistentModel.Type] = PersistenceSchemaV1.models,
        storage: StorageMode = .appGroup,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil
    ) throws {
        let schema = Schema(models)
        let configuration: ModelConfiguration

        switch storage {
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        case .privateStore(let url):
            configuration = ModelConfiguration(schema: schema, url: url)
        case .appGroup:
            guard let directory = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) else {
                throw PersistenceError.appGroupUnavailable
            }
            let url = directory.appending(path: "ChapterFlow.store")
            configuration = ModelConfiguration(schema: schema, url: url)
        }

        if let migrationPlan {
            container = try ModelContainer(
                for: schema,
                migrationPlan: migrationPlan,
                configurations: configuration
            )
        } else {
            container = try ModelContainer(for: schema, configurations: configuration)
        }
    }

    /// Wraps an existing container (e.g. one built elsewhere or for previews).
    public init(container: ModelContainer) {
        self.container = container
    }

    /// Convenience: the default core schema with its migration plan.
    public static func makeDefault(storage: StorageMode = .appGroup) throws -> PersistenceController {
        try PersistenceController(
            models: PersistenceSchemaV1.models,
            storage: storage,
            migrationPlan: PersistenceMigrationPlan.self
        )
    }

    /// Creates a fresh, non-autosaving context for background work on the calling task.
    ///
    /// The returned `ModelContext` is **not** `Sendable`; use it only on the task that
    /// created it. For cross-actor background work prefer ``BackgroundStore``.
    public func newBackgroundContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    /// A background store bound to this controller's container.
    public func backgroundStore() -> BackgroundStore {
        BackgroundStore(modelContainer: container)
    }
}

// MARK: - Background store

/// A model actor providing a serialized background context for off-main writes.
@ModelActor
public actor BackgroundStore {
    /// Inserts a model and saves.
    public func insert<M: PersistentModel>(_ model: M) throws {
        modelContext.insert(model)
        try modelContext.save()
    }

    /// Deletes every instance of the given model type and saves.
    public func deleteAll<M: PersistentModel>(_ type: M.Type) throws {
        try modelContext.delete(model: M.self)
        try modelContext.save()
    }

    /// Counts instances of the given model type.
    public func count<M: PersistentModel>(_ type: M.Type) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<M>())
    }
}
