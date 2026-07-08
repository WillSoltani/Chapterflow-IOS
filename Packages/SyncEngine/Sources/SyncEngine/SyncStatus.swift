import Foundation

// MARK: - SyncPhase

/// The current operational phase of the sync engine.
public enum SyncPhase: String, Sendable, Equatable {
    /// No mutations are pending and no network activity is in progress.
    case idle
    /// The engine is actively uploading queued mutations.
    case syncing
    /// One or more mutations have reached terminal failure.
    case error
}

// MARK: - SyncStatus

/// Observable sync status for the subtle sync-status UI indicator.
///
/// Updated on `@MainActor` by ``SyncEngine`` whenever the drain loop changes
/// state. Views bind directly; no extra adapters are needed.
///
/// ```swift
/// @Environment(\.syncStatus) private var syncStatus
/// // or
/// SyncStatusIndicatorView(status: engine.status)
/// ```
///
/// All writes happen on `@MainActor` (via `MainActor.run` inside `SyncEngine`);
/// all reads happen on `@MainActor` (SwiftUI observation). The `@unchecked Sendable`
/// conformance is safe because writes and reads are serialised through the main actor.
@Observable
public final class SyncStatus: @unchecked Sendable {
    /// Current operational phase of the engine.
    public var phase: SyncPhase = .idle

    /// Number of mutations still waiting in the outbox (including in-flight ones).
    public var pendingCount: Int = 0

    /// Human-readable description of the most recent terminal failure, if any.
    public var lastError: String?

    /// The last time the outbox was fully drained to empty. `nil` before the first successful sync.
    public var lastSyncedDate: Date?

    public init() {}
}
