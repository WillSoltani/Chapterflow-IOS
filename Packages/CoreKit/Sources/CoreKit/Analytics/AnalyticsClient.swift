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

// MARK: - Wire models

/// One analytics event as sent to the backend.
struct AnalyticsWireEvent: Codable, Sendable, Equatable {
    let name: String
    let properties: [String: String]
    let timestamp: Date
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

    // In-memory fallback used when diskQueue is nil.
    private var memoryBuffer: [AnalyticsWireEvent] = []
    private var optedOut: Bool

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Public initializer with in-memory buffering only. Use ``makeDurable(transport:batchSize:optedOut:)``
    /// for the disk-backed production path.
    public init(
        transport: AnalyticsTransport,
        batchSize: Int = 20,
        optedOut: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.batchSize = max(1, batchSize)
        self.optedOut = optedOut
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
        diskQueue: DiskQueue?
    ) {
        self.transport = transport
        self.batchSize = max(1, batchSize)
        self.optedOut = optedOut
        self.now = now
        self.diskQueue = diskQueue
    }

    // MARK: - Factory

    /// Creates a production client backed by a disk queue in Application Support.
    ///
    /// The queue file survives process kills and crashes. Call `flush()` early in
    /// the app lifecycle to drain any events from the previous session.
    public static func makeDurable(
        transport: AnalyticsTransport,
        batchSize: Int = 20,
        optedOut: Bool = false
    ) -> DefaultAnalyticsClient {
        let queue: DiskQueue? = {
            let fm = FileManager.default
            guard let appSupport = fm.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { return nil }
            let dir = appSupport.appendingPathComponent("com.chapterflow", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return DiskQueue(fileURL: dir.appendingPathComponent("analytics_queue.json"))
        }()
        return DefaultAnalyticsClient(
            transport: transport,
            batchSize: batchSize,
            optedOut: optedOut,
            diskQueue: queue
        )
    }

    // MARK: - AnalyticsClient (non-throwing, fire-and-forget)

    public nonisolated func track(_ event: AnalyticsEvent) {
        Task { await self.record(event) }
    }

    public nonisolated func beacon(_ name: String, properties: [String: String]) {
        Task { await self.deliverBeacon(name: name, properties: properties) }
    }

    // MARK: - Opt-out

    /// Toggles analytics collection. When opting out, buffered events (memory
    /// and disk) are discarded so nothing already queued is sent.
    public func setOptedOut(_ value: Bool) {
        optedOut = value
        if value {
            memoryBuffer.removeAll()
            Task { _ = try? await diskQueue?.clear() }
        }
    }

    // MARK: - Internal async core (also the seam used by tests)

    /// Records an event, persisting to disk immediately (when a disk queue is
    /// configured) and auto-flushing once the batch size is reached.
    func record(_ event: AnalyticsEvent) async {
        guard !optedOut else { return }
        let wireEvent = AnalyticsWireEvent(
            name: event.name,
            properties: event.properties,
            timestamp: now()
        )

        if let diskQueue {
            do {
                let count = try await diskQueue.enqueue([wireEvent])
                if count >= batchSize { await flush() }
            } catch {
                log.error("disk enqueue failed: \(error.localizedDescription)")
            }
        } else {
            memoryBuffer.append(wireEvent)
            if memoryBuffer.count >= batchSize { await flush() }
        }
    }

    public func flush() async {
        if let diskQueue {
            let batch = await diskQueue.dequeueAll()
            guard !batch.isEmpty else { return }
            do {
                let payload = try encoder.encode(AnalyticsTrackBatch(events: batch))
                try await transport.send(path: Path.track, payload: payload)
            } catch {
                // Re-queue on send failure so events survive until next launch.
                try? await diskQueue.enqueue(batch)
                log.error("track flush re-queued \(batch.count) event(s): \(error.localizedDescription)")
            }
        } else {
            guard !memoryBuffer.isEmpty else { return }
            let batch = memoryBuffer
            memoryBuffer.removeAll()
            do {
                let payload = try encoder.encode(AnalyticsTrackBatch(events: batch))
                try await transport.send(path: Path.track, payload: payload)
            } catch {
                log.error("track flush dropped \(batch.count) event(s): \(error.localizedDescription)")
            }
        }
    }

    func deliverBeacon(name: String, properties: [String: String]) async {
        guard !optedOut else { return }
        do {
            let event = AnalyticsWireEvent(name: name, properties: properties, timestamp: now())
            let payload = try encoder.encode(event)
            try await transport.send(path: Path.beacon, payload: payload)
        } catch {
            log.error("beacon '\(name)' dropped: \(error.localizedDescription)")
        }
    }

    /// Current number of in-memory buffered events (test seam for memory path).
    var bufferedCount: Int { memoryBuffer.count }

    /// Number of events currently persisted on disk (available when disk-backed).
    func diskQueueCount() async -> Int {
        await diskQueue?.count ?? 0
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
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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
