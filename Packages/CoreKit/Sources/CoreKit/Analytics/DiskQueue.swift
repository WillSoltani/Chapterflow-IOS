import Foundation

/// A crash-safe, disk-backed FIFO queue for ``QueuedAnalyticsEvent`` values.
///
/// Events are persisted atomically (via `Data.write(to:options:.atomic)`) so
/// a crash mid-write never corrupts the file. The queue holds at most
/// `maxSize` events and silently drops the oldest once the ceiling is reached,
/// ensuring bounded storage.
///
/// This is an `actor` so all file operations are serialised.
actor DiskQueue {
    private let fileURL: URL
    let maxSize: Int
    private let log = AppLog(category: .analytics)

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(fileURL: URL, maxSize: Int = 500) {
        self.fileURL = fileURL
        self.maxSize = maxSize
    }

    // MARK: - Public API

    /// Appends `events` to the queue and returns the new total count.
    /// Drops the oldest events if the count would exceed `maxSize`.
    @discardableResult
    func enqueue(_ events: [AnalyticsWireEvent]) throws -> Int {
        try enqueueQueued(events.map { QueuedAnalyticsEvent(event: $0) })
    }

    private func enqueueQueued(_ events: [QueuedAnalyticsEvent]) throws -> Int {
        var current = load()
        current.append(contentsOf: events)
        if current.count > maxSize {
            current.removeFirst(current.count - maxSize)
        }
        try save(current)
        return current.count
    }

    /// Session-bound enqueue. The file mutation participates in the same
    /// generation barrier as the owning account scope.
    @discardableResult
    func enqueue(
        _ events: [QueuedAnalyticsEvent],
        permit: SessionWorkPermit,
        ticket: UInt64
    ) throws -> Int {
        try permit.commit(ticket) {
            try enqueueQueued(events)
        }
    }

    /// Returns the current queue without removing it. Delivery removes the
    /// prefix only after the transport succeeds, so a boundary during send
    /// cannot strand a dequeued batch.
    func snapshot(permit: SessionWorkPermit, ticket: UInt64) throws -> [QueuedAnalyticsEvent] {
        try permit.commit(ticket) {
            load()
        }
    }

    /// Removes only entries whose queue-local identities were delivered.
    /// A blocked send may allow max-size rollover to evict part of its original
    /// snapshot; identity reconciliation preserves every newly enqueued tail.
    func removeDelivered(
        _ delivered: [QueuedAnalyticsEvent],
        permit: SessionWorkPermit,
        ticket: UInt64
    ) throws {
        try permit.commit(ticket) {
            guard !delivered.isEmpty else { return }
            let deliveredIDs = Set(delivered.map(\.id))
            var current = load()
            while let first = current.first, deliveredIDs.contains(first.id) {
                current.removeFirst()
            }
            try save(current)
        }
    }

    /// Removes and returns all queued events atomically.
    /// Returns an empty array if the queue is empty or the file cannot be read.
    func dequeueAll() -> [AnalyticsWireEvent] {
        let events = load()
        if !events.isEmpty {
            try? save([])
        }
        return events.map(\.event)
    }

    /// Discards all queued events.
    func clear() throws {
        try save([])
    }

    func clear(permit: SessionWorkPermit, ticket: UInt64) throws {
        try permit.commit(ticket) {
            try clear()
        }
    }

    /// The current number of queued events (0 on read failure).
    var count: Int { load().count }

    /// Whether the queue is empty.
    var isEmpty: Bool { load().isEmpty }

    // MARK: - Private

    private func load() -> [QueuedAnalyticsEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode([QueuedAnalyticsEvent].self, from: data)
        } catch {
            log.error("disk queue load failed")
            return []
        }
    }

    private func save(_ events: [QueuedAnalyticsEvent]) throws {
        let data = try Self.encoder.encode(events)
        // `.atomic` writes to a temp file then renames — crash-safe.
        try data.write(to: fileURL, options: .atomic)
    }
}
