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

/// V1: initial schema — key/value cache only.
public enum PersistenceSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CachedKeyValue.self]
    }
}

/// V2: adds reader annotations (highlights, notes, bookmarks) and the offline upload outbox.
public enum PersistenceSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CachedKeyValue.self, LocalAnnotation.self, PendingAnnotationUpload.self]
    }
}

/// V3: adds the offline outbox for FSRS review grades (P5.9).
public enum PersistenceSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CachedKeyValue.self, LocalAnnotation.self, PendingAnnotationUpload.self, PendingReviewGrade.self]
    }
}

/// V4: adds offline outbox for commitment creates/updates (P5.10).
public enum PersistenceSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CachedKeyValue.self, LocalAnnotation.self, PendingAnnotationUpload.self,
         PendingReviewGrade.self, PendingCommitmentUpload.self]
    }
}

/// Migration plan. Lightweight migrations require no field renames or transformations.
public enum PersistenceMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [PersistenceSchemaV1.self, PersistenceSchemaV2.self,
         PersistenceSchemaV3.self, PersistenceSchemaV4.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: PersistenceSchemaV1.self, toVersion: PersistenceSchemaV2.self),
            .lightweight(fromVersion: PersistenceSchemaV2.self, toVersion: PersistenceSchemaV3.self),
            .lightweight(fromVersion: PersistenceSchemaV3.self, toVersion: PersistenceSchemaV4.self),
        ]
    }
}

// MARK: - Controller

/// Where the SwiftData store is physically located.
public enum StorageMode: Sendable, Equatable {
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
///
/// - Important: **App extensions (widgets, share extensions, etc.) must never call
///   this initialiser with a persistent storage mode.** Multi-process SQLite access
///   (main app + extension both writing) is a data-corruption hazard that SwiftData
///   does not protect against. Extensions must consume the lightweight App-Group
///   key/value snapshot written by the main app instead (see the P8.0 shared-state
///   module). This constraint is enforced at debug-build time by a `precondition`.
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
        models: [any PersistentModel.Type] = PersistenceSchemaV4.models,
        storage: StorageMode = .appGroup,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil
    ) throws {
        // Extensions that open a persistent SwiftData store risk corrupting the
        // on-disk SQLite database when the main app is also running. Catch this
        // in debug builds so the mistake is caught before it reaches production.
        // Use `.inMemory` storage in tests and `.inMemory`/App-Group snapshot in
        // extensions.
        precondition(
            storage == .inMemory || !Bundle.main.bundlePath.hasSuffix(".appex"),
            "PersistenceController: App extensions must not open a persistent SwiftData " +
            "container. Use the App Group key/value snapshot for extension data access."
        )
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

    /// Convenience: the default core schema (V4) with its migration plan.
    public static func makeDefault(storage: StorageMode = .appGroup) throws -> PersistenceController {
        try PersistenceController(
            models: PersistenceSchemaV4.models,
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
