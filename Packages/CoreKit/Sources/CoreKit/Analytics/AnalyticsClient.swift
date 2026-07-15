import Foundation

/// Fire-and-forget analytics sink.
///
/// `track`/`beacon` are intentionally non-`async` and non-throwing: analytics is
/// best-effort and must never surface an error to the UI or block a user action.
/// Delivery happens on a background task; failures are logged and dropped.
public protocol AnalyticsClient: Sendable {
    /// Records a typed funnel event. Buffered and delivered in batches.
    func track(_ event: AnalyticsEvent)
    /// Sends a lightweight named beacon immediately (best-effort), e.g. for
    /// moments where the app may be about to background/terminate.
    func beacon(_ name: String, properties: [String: String])
    /// Forces any buffered events to be delivered now.
    func flush() async
}

public extension AnalyticsClient {
    func beacon(_ name: String) { beacon(name, properties: [:]) }
}

/// The transport that actually delivers analytics payloads. Abstracted so the
/// default client stays free of any `Networking` dependency and is trivially
/// testable with a spy.
public protocol AnalyticsTransport: Sendable {
    /// POSTs `payload` to `path` (relative to the API base). May throw; the
    /// caller treats all failures as best-effort drops.
    func send(path: String, payload: Data) async throws
}

/// Privacy-safe failures raised while opening required account-owned analytics storage.
///
/// Cases intentionally carry no paths or namespace values so callers can report the
/// category without exposing an account-derived identifier.
public enum AnalyticsDurableStorageFailure: Error, Equatable, Sendable {
    /// The supplied namespace was not an opaque namespace produced by `AccountContext`.
    case invalidStorageNamespace
    /// The account-owned queue directory could not be located or created.
    case requiredAccountDirectory
}

// MARK: - Wire models

/// One analytics event as sent to the backend.
struct AnalyticsWireEvent: Codable, Sendable, Equatable {
    let name: String
    let properties: [String: String]
    let timestamp: Date
}

/// Durable queue identity kept separate from the backend wire contract.
struct QueuedAnalyticsEvent: Codable, Sendable, Equatable {
    let id: UUID
    let event: AnalyticsWireEvent

    private enum CodingKeys: String, CodingKey {
        case id, name, properties, timestamp
    }

    init(id: UUID = UUID(), event: AnalyticsWireEvent) {
        self.id = id
        self.event = event
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        event = try AnalyticsWireEvent(
            name: container.decode(String.self, forKey: .name),
            properties: container.decode([String: String].self, forKey: .properties),
            timestamp: container.decode(Date.self, forKey: .timestamp)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(event.name, forKey: .name)
        try container.encode(event.properties, forKey: .properties)
        try container.encode(event.timestamp, forKey: .timestamp)
    }
}

/// The batched payload for `POST /book/me/analytics/track`.
struct AnalyticsTrackBatch: Encodable, Sendable {
    let events: [AnalyticsWireEvent]
}

// MARK: - Default client

/// The production `AnalyticsClient`: buffers events and flushes them in batches,
/// never throwing to callers. Honors an analytics opt-out.
///
/// When initialised with a `diskQueue`, events are persisted to disk immediately
/// on every `track()` call and survive process kills / crashes. On next launch,
/// call `flush()` early in the app lifecycle to drain any residual events from
/// the previous session.
///
/// When `diskQueue` is `nil` (the default), the client uses an in-memory buffer —
/// suitable for tests and SwiftUI Previews.
public actor DefaultAnalyticsClient: AnalyticsClient {
    /// Relative API paths for the two analytics endpoints.
    enum Path {
        static let track = "/book/me/analytics/track"
        static let beacon = "/book/me/analytics/beacon"
    }

    private let transport: AnalyticsTransport
    private let batchSize: Int
    private let now: @Sendable () -> Date
    private let log = AppLog(category: .analytics)
    // Disk-backed queue for durability. nil = in-memory only (tests/previews).
    private let diskQueue: DiskQueue?
    nonisolated private let workPermit: SessionWorkPermit

    // In-memory fallback used when diskQueue is nil.
    private var memoryBuffer: [QueuedAnalyticsEvent] = []
    private var optedOut: Bool
    private var sessionSuspended = false
    private var pendingWork: [UUID: Task<Void, Never>] = [:]
    private var isFlushInProgress = false
    private var flushRequested = false
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Public initializer with in-memory buffering only. Use
    /// ``makeDurable(transport:batchSize:optedOut:storageNamespace:)``
    /// for the disk-backed production path.
    public init(
        transport: AnalyticsTransport,
        batchSize: Int = 20,
        optedOut: Bool = false,
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.batchSize = max(1, batchSize)
        self.optedOut = optedOut
        self.workPermit = workPermit
        self.now = now
        self.diskQueue = nil
    }

    /// Internal initializer for tests: allows injecting a `DiskQueue` directly
    /// (`DiskQueue` is internal so it cannot appear in a `public` signature).
    init(
        transport: AnalyticsTransport,
        batchSize: Int = 20,
        optedOut: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() },
        diskQueue: DiskQueue?,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        self.transport = transport
        self.batchSize = max(1, batchSize)
        self.optedOut = optedOut
        self.now = now
        self.diskQueue = diskQueue
        self.workPermit = workPermit
    }

    // MARK: - Factory

    /// Creates a production client backed by a disk queue in Application Support.
    ///
    /// The queue file survives process kills and crashes. Call `flush()` early in
    /// the app lifecycle to drain any events from the previous session.
    public static func makeDurable(
        transport: AnalyticsTransport,
        batchSize: Int = 20,
        optedOut: Bool = false,
        storageNamespace: String,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) throws -> DefaultAnalyticsClient {
        let applicationSupport: URL
        do {
            applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw AnalyticsDurableStorageFailure.requiredAccountDirectory
        }

        return try makeDurable(
            transport: transport,
            batchSize: batchSize,
            optedOut: optedOut,
            storageNamespace: storageNamespace,
            applicationSupportDirectory: applicationSupport,
            workPermit: workPermit
        )
    }

    /// Deterministic filesystem seam used by package tests.
    static func makeDurable(
        transport: AnalyticsTransport,
        batchSize: Int = 20,
        optedOut: Bool = false,
        storageNamespace: String,
        applicationSupportDirectory: URL,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) throws -> DefaultAnalyticsClient {
        guard isValidAccountStorageNamespace(storageNamespace) else {
            throw AnalyticsDurableStorageFailure.invalidStorageNamespace
        }

        let directory = applicationSupportDirectory
            .appendingPathComponent("com.chapterflow", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(storageNamespace, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw AnalyticsDurableStorageFailure.requiredAccountDirectory
        }

        let queue = DiskQueue(
            fileURL: directory.appendingPathComponent("analytics_queue.json")
        )
        return DefaultAnalyticsClient(
            transport: transport,
            batchSize: batchSize,
            optedOut: optedOut,
            diskQueue: queue,
            workPermit: workPermit
        )
    }

    private static func isValidAccountStorageNamespace(_ value: String) -> Bool {
        let prefix = "account-v1-"
        guard value.hasPrefix(prefix) else { return false }
        let digest = value.dropFirst(prefix.count)
        guard digest.count == 64 else { return false }
        return digest.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character)
        }
    }

    // MARK: - AnalyticsClient (non-throwing, fire-and-forget)

    public nonisolated func track(_ event: AnalyticsEvent) {
        guard let ticket = try? workPermit.begin() else { return }
        Task { await self.scheduleRecord(event, ticket: ticket) }
    }

    public nonisolated func beacon(_ name: String, properties: [String: String]) {
        guard let ticket = try? workPermit.begin() else { return }
        Task { await self.scheduleBeacon(name: name, properties: properties, ticket: ticket) }
    }

    // MARK: - Opt-out

    /// Toggles analytics collection. When opting out, buffered events (memory
    /// and disk) are discarded so nothing already queued is sent.
    public func setOptedOut(_ value: Bool) async {
        optedOut = value
        if value {
            memoryBuffer.removeAll()
            if let ticket = try? workPermit.begin() {
                _ = try? await diskQueue?.clear(permit: workPermit, ticket: ticket)
            }
        }
    }

    /// Stops this account-owned client without deleting its durable queue.
    ///
    /// Ordinary sign-out is a lifetime boundary, not an analytics-consent
    /// change. Pending events remain in the opaque account namespace so a
    /// later session for the same account can resume delivery under D-05.
    public func suspendForSessionBoundary() async {
        sessionSuspended = true
        let tasks = Array(pendingWork.values)
        tasks.forEach { $0.cancel() }
        for task in tasks {
            await task.value
        }
        pendingWork.removeAll()
    }

    /// Re-enables the same account-owned client after a reversible sign-out
    /// attempt fails. Consent state remains independent from session suspension.
    public func resumeAfterSessionBoundary() {
        sessionSuspended = false
    }

    // MARK: - Internal async core (also the seam used by tests)

    /// Records an event, persisting to disk immediately (when a disk queue is
    /// configured) and auto-flushing once the batch size is reached.
    func record(_ event: AnalyticsEvent) async {
        guard let ticket = try? workPermit.begin() else { return }
        await record(event, ticket: ticket)
    }

    private func record(_ event: AnalyticsEvent, ticket: UInt64) async {
        guard !Task.isCancelled, !optedOut, !sessionSuspended else { return }
        guard (try? workPermit.validate(ticket)) != nil else { return }
        let wireEvent = AnalyticsWireEvent(
            name: event.name,
            properties: event.properties,
            timestamp: now()
        )
        let queuedEvent = QueuedAnalyticsEvent(event: wireEvent)

        if let diskQueue {
            do {
                let count = try await diskQueue.enqueue(
                    [queuedEvent],
                    permit: workPermit,
                    ticket: ticket
                )
                if count >= batchSize { await flush() }
            } catch is CancellationError {
                return
            } catch {
                log.error("disk enqueue failed")
            }
        } else {
            do {
                try workPermit.commit(ticket) {
                    memoryBuffer.append(queuedEvent)
                }
                if memoryBuffer.count >= batchSize { await flush() }
            } catch is CancellationError {
                return
            } catch {
                log.error("memory enqueue failed")
            }
        }
    }

    public func flush() async {
        guard let ticket = try? workPermit.begin() else { return }
        guard !Task.isCancelled, !optedOut, !sessionSuspended else { return }
        guard (try? workPermit.validate(ticket)) != nil else { return }
        if isFlushInProgress {
            flushRequested = true
            await withCheckedContinuation { continuation in
                flushWaiters.append(continuation)
            }
            return
        }

        isFlushInProgress = true
        flushRequested = false

        if let diskQueue {
            guard let queuedBatch = try? await diskQueue.snapshot(
                permit: workPermit,
                ticket: ticket
            ) else {
                await finishFlushCycle(ticket: ticket)
                return
            }
            guard !queuedBatch.isEmpty else {
                await finishFlushCycle(ticket: ticket)
                return
            }
            let batch = queuedBatch.map(\.event)
            do {
                let payload = try encoder.encode(AnalyticsTrackBatch(events: batch))
                try await transport.send(path: Path.track, payload: payload)
                if !Task.isCancelled {
                    try await diskQueue.removeDelivered(
                        queuedBatch,
                        permit: workPermit,
                        ticket: ticket
                    )
                }
            } catch is CancellationError {
                // The snapshot remains durable across a session boundary.
            } catch {
                // The snapshot remains durable until a successful delivery.
                log.error("track flush retained \(batch.count) event(s)")
            }
        } else {
            guard !memoryBuffer.isEmpty else {
                await finishFlushCycle(ticket: ticket)
                return
            }
            let queuedBatch = memoryBuffer
            let batch = queuedBatch.map(\.event)
            do {
                let payload = try encoder.encode(AnalyticsTrackBatch(events: batch))
                try await transport.send(path: Path.track, payload: payload)
                try workPermit.commit(ticket) {
                    let deliveredIDs = Set(queuedBatch.map(\.id))
                    memoryBuffer.removeAll { deliveredIDs.contains($0.id) }
                }
            } catch is CancellationError {
                // The snapshot remains in memory across a reversible boundary.
            } catch {
                log.error("track flush retained \(batch.count) event(s): \(error.localizedDescription)")
            }
        }

        await finishFlushCycle(ticket: ticket)
    }

    /// Completes one single-flight snapshot and services an overlapping caller
    /// without allowing two transport/removal cycles to overlap.
    private func finishFlushCycle(ticket: UInt64) async {
        let shouldRepeat = flushRequested &&
            !Task.isCancelled &&
            !optedOut &&
            !sessionSuspended &&
            (try? workPermit.validate(ticket)) != nil
        isFlushInProgress = false

        if shouldRepeat {
            await flush()
            return
        }

        flushRequested = false
        let waiters = flushWaiters
        flushWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    func deliverBeacon(name: String, properties: [String: String]) async {
        guard let ticket = try? workPermit.begin() else { return }
        guard !Task.isCancelled, !optedOut, !sessionSuspended else { return }
        guard (try? workPermit.validate(ticket)) != nil else { return }
        do {
            let event = AnalyticsWireEvent(name: name, properties: properties, timestamp: now())
            let payload = try encoder.encode(event)
            try await transport.send(path: Path.beacon, payload: payload)
        } catch is CancellationError {
            return
        } catch {
            log.error("analytics beacon dropped")
        }
    }

    /// Current number of in-memory buffered events (test seam + debug menu).
    public var bufferedCount: Int { memoryBuffer.count }

    /// Deterministic single-flight test seam.
    var hasPendingFlushForTest: Bool { !flushWaiters.isEmpty }

    /// Number of events currently persisted on disk (available when disk-backed).
    public func diskQueueCount() async -> Int {
        await diskQueue?.count ?? 0
    }

    private func scheduleRecord(_ event: AnalyticsEvent, ticket: UInt64) {
        guard !optedOut, !sessionSuspended else { return }
        guard (try? workPermit.validate(ticket)) != nil else { return }
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.record(event, ticket: ticket)
            await self.finishPendingWork(id)
        }
        pendingWork[id] = task
    }

    private func scheduleBeacon(
        name: String,
        properties: [String: String],
        ticket: UInt64
    ) {
        guard !optedOut, !sessionSuspended else { return }
        guard (try? workPermit.validate(ticket)) != nil else { return }
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.deliverBeacon(name: name, properties: properties)
            await self.finishPendingWork(id)
        }
        pendingWork[id] = task
    }

    private func finishPendingWork(_ id: UUID) {
        pendingWork[id] = nil
    }
}

// MARK: - URLSession transport

/// The default `AnalyticsTransport`, posting JSON to the API with a Bearer token.
///
/// Kept deliberately minimal (no envelope decoding, no retries) because
/// analytics delivery is best-effort. Lives in `CoreKit` to avoid a dependency
/// on `Networking` (which itself depends on `CoreKit`).
public struct URLSessionAnalyticsTransport: AnalyticsTransport {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () async -> String?

    /// - Parameters:
    ///   - baseURL: The API base URL (e.g. from `AppConfig.apiBaseURL`).
    ///   - session: The `URLSession` to use (injectable for tests).
    ///   - tokenProvider: Supplies the current Cognito `id_token`, if any.
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () async -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func send(path: String, payload: Data) async throws {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let token = await tokenProvider() else {
            throw AppError.unauthenticated
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = payload
        _ = try await session.data(for: request)
    }
}

/// A no-op analytics client for previews, tests, and disabled states.
public struct NoopAnalyticsClient: AnalyticsClient {
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
    public func beacon(_ name: String, properties: [String: String]) {}
    public func flush() async {}
}
