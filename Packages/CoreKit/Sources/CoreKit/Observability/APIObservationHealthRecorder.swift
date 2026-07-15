import os

/// Closed account/session state attached to a development health snapshot.
public enum APIObservationSessionState: String, Sendable, Equatable {
    case signedOut = "signed_out"
    case signedIn = "signed_in"
}

/// A narrow, immutable view of recent privacy-safe API health.
///
/// Every event has already passed through `APIRequestObservation`'s closed
/// sanitizer. The session generation is process-local and has no relationship
/// to a user or account identifier.
public struct APIObservationHealthSnapshot: Sendable, Equatable {
    public let capacity: Int
    public let events: [APIRequestObservation]
    public let sessionGeneration: UInt64
    public let sessionState: APIObservationSessionState
}

/// A process-local, lock-isolated recorder for recent API health observations.
///
/// Storage is fixed at 128 events, performs no I/O, and never creates tasks.
/// Session transitions synchronously clear the buffer and rotate an ephemeral
/// generation. Context-aware records from an older generation are rejected.
public final class APIObservationHealthRecorder: APIClientObserver, Sendable {
    public static let capacity = 128

    private struct State: Sendable {
        var events: [APIRequestObservation] = []
        var sessionGeneration: UInt64 = 0
        var sessionState: APIObservationSessionState
        var acceptsEvents = true
        var generationExhausted = false
    }

    private let storage: OSAllocatedUnfairLock<State>

    public init(initialSessionState: APIObservationSessionState = .signedOut) {
        storage = OSAllocatedUnfairLock(initialState: State(sessionState: initialSessionState))
    }

    public func captureContext() -> APIObservationContext {
        storage.withLock { state in
            guard state.acceptsEvents else { return APIObservationContext() }
            return APIObservationContext(sessionGeneration: state.sessionGeneration)
        }
    }

    /// Records an already-closed event in the current generation.
    ///
    /// Direct recording is useful for other synchronous composition boundaries;
    /// `APIClient` uses the context-aware overload below.
    public func record(_ event: APIRequestObservation) {
        storage.withLock { state in
            guard state.acceptsEvents else { return }
            Self.append(event, to: &state.events)
        }
    }

    public func record(_ event: APIRequestObservation, context: APIObservationContext) {
        storage.withLock { state in
            guard
                state.acceptsEvents,
                context.sessionGeneration == state.sessionGeneration
            else { return }
            Self.append(event, to: &state.events)
        }
    }

    public func snapshot() -> APIObservationHealthSnapshot {
        storage.withLock { state in
            APIObservationHealthSnapshot(
                capacity: Self.capacity,
                events: state.events,
                sessionGeneration: state.sessionGeneration,
                sessionState: state.sessionState
            )
        }
    }

    /// Atomically clears and rotates into a stable closed session state.
    public func transition(to sessionState: APIObservationSessionState) {
        storage.withLock { state in
            Self.beginTransition(state: &state)
            Self.completeTransition(to: sessionState, state: &state)
        }
    }

    /// Clears and rotates synchronously before an observed auth state mutates.
    /// Events are rejected until `completeSessionTransition(to:)` runs.
    public func beginSessionTransition() {
        storage.withLock { state in
            Self.beginTransition(state: &state)
        }
    }

    /// Completes a transition without advancing the generation a second time.
    public func completeSessionTransition(to sessionState: APIObservationSessionState) {
        storage.withLock { state in
            Self.completeTransition(to: sessionState, state: &state)
        }
    }

    private static func append(
        _ event: APIRequestObservation,
        to events: inout [APIRequestObservation]
    ) {
        events.append(event)
        let overflow = events.count - capacity
        if overflow > 0 {
            events.removeFirst(overflow)
        }
    }

    private static func beginTransition(state: inout State) {
        state.events.removeAll(keepingCapacity: true)
        state.sessionState = .signedOut
        state.acceptsEvents = false

        guard state.sessionGeneration < UInt64.max else {
            // Fail closed rather than ever reusing an exhausted generation.
            state.generationExhausted = true
            return
        }
        state.sessionGeneration += 1
    }

    private static func completeTransition(
        to sessionState: APIObservationSessionState,
        state: inout State
    ) {
        state.sessionState = sessionState
        state.acceptsEvents = !state.generationExhausted
    }
}
