import Foundation

/// A crash-safe, disk-backed FIFO queue for ``AnalyticsWireEvent`` values.
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
        var current = load()
        current.append(contentsOf: events)
        if current.count > maxSize {
            current.removeFirst(current.count - maxSize)
        }
        try save(current)
        return current.count
    }

    /// Removes and returns all queued events atomically.
    /// Returns an empty array if the queue is empty or the file cannot be read.
    func dequeueAll() -> [AnalyticsWireEvent] {
        let events = load()
        if !events.isEmpty {
            try? save([])
        }
        return events
    }

    /// Discards all queued events.
    func clear() throws {
        try save([])
    }

    /// The current number of queued events (0 on read failure).
    var count: Int { load().count }

    // MARK: - Private

    private func load() -> [AnalyticsWireEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode([AnalyticsWireEvent].self, from: data)
        } catch {
            log.error("disk queue load failed: \(error.localizedDescription)")
            return []
        }
    }

    private func save(_ events: [AnalyticsWireEvent]) throws {
        let data = try Self.encoder.encode(events)
        // `.atomic` writes to a temp file then renames — crash-safe.
        try data.write(to: fileURL, options: .atomic)
    }
}
