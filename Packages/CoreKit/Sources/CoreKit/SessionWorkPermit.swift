import os
import Dispatch

/// A synchronous, revocable generation gate for one account session.
///
/// Transport work uses `begin()`/`validate(_:)` around suspension points.
/// Durable local writers use `commit(_:_:)`, which validates and performs the
/// non-suspending commit while holding the same lock used by
/// `quiesce()`/`invalidate()`. Consequently, once either boundary method
/// returns, no prior-generation local commit is still running or can begin.
public final class SessionWorkPermit: Sendable {
    public enum State: Sendable, Equatable {
        case active
        case quiesced
        case invalidated
    }

    private struct Storage: Sendable {
        var state: State
        var generation: UInt64 = 0
    }

    private let storage: OSAllocatedUnfairLock<Storage>
    private let commits = DispatchGroup()

    public init(initialState: State = .active) {
        storage = OSAllocatedUnfairLock(initialState: Storage(state: initialState))
    }

    public func begin() throws -> UInt64 {
        try storage.withLock { storage in
            guard storage.state == .active else { throw CancellationError() }
            return storage.generation
        }
    }

    public func validate(_ ticket: UInt64) throws {
        try storage.withLock { storage in
            try Self.validate(ticket, storage: storage)
        }
    }

    /// Performs one non-suspending local commit atomically with respect to
    /// scope quiesce/invalidation.
    @discardableResult
    public func commit<Value>(
        _ ticket: UInt64,
        _ operation: () throws -> Value
    ) throws -> Value {
        try storage.withLock { storage in
            try Self.validate(ticket, storage: storage)
            commits.enter()
        }
        defer { commits.leave() }
        return try operation()
    }

    public func quiesce() {
        let transitioned = storage.withLock { storage -> Bool in
            guard storage.state == .active else { return false }
            storage.generation &+= 1
            storage.state = .quiesced
            return true
        }
        if transitioned == true { commits.wait() }
    }

    public func resume() {
        storage.withLock { storage in
            guard storage.state == .quiesced else { return }
            storage.generation &+= 1
            storage.state = .active
        }
    }

    public func invalidate() {
        let transitioned = storage.withLock { storage -> Bool in
            guard storage.state != .invalidated else { return false }
            storage.generation &+= 1
            storage.state = .invalidated
            return true
        }
        if transitioned == true { commits.wait() }
    }

    public func currentState() -> State {
        storage.withLock(\.state)
    }

    private static func validate(_ ticket: UInt64, storage: Storage) throws {
        guard storage.state == .active, ticket == storage.generation else {
            throw CancellationError()
        }
    }
}
