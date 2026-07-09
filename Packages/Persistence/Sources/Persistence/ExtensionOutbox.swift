import Foundation

/// Reads and writes ``PendingExtensionItem`` values in the App Group `UserDefaults`.
///
/// **Writers** — Share Extension and Action Extension — call ``write(_:)`` from
/// their extension process to enqueue an item.
///
/// **Reader** — the main app — calls ``readAll()`` then ``clear()`` on every foreground
/// activation to drain the outbox and process pending items.
///
/// **RF4 compliance**: No SwiftData store is opened.  The entire outbox lives in App
/// Group `UserDefaults`, which is safe for extension processes to access concurrently
/// with the main app.
///
/// **Thread safety**: Individual `UserDefaults` reads and writes are thread-safe.
/// The append-then-read pattern is NOT atomic, but the only writer is the extension
/// process and the only reader is the main app process — concurrent access is therefore
/// extremely rare in practice. `@unchecked Sendable` mirrors the same pattern used
/// by ``SharedStateReader``.
public struct ExtensionOutbox: @unchecked Sendable {

    /// The `UserDefaults` key under which the JSON-encoded item array is stored.
    public static let outboxKey = "extension.outbox"

    private let defaults: UserDefaults

    /// Creates an outbox backed by the given App Group suite name.
    ///
    /// Pass `nil` (or omit the argument) to use ``AppGroup/identifier``.
    /// Pass a custom string in tests to use an isolated `UserDefaults` instance.
    public init(suiteName: String? = nil) {
        self.defaults = UserDefaults(suiteName: suiteName ?? AppGroup.identifier) ?? .standard
    }

    // MARK: - Extension-side API

    /// Appends `item` to the outbox.
    ///
    /// Call this from Share/Action extension processes.  The main app drains the
    /// outbox on the next foreground activation.
    public func write(_ item: PendingExtensionItem) {
        var items = readAll()
        items.append(item)
        store(items)
    }

    // MARK: - Main-app-side API

    /// Returns all pending items in insertion order.
    ///
    /// Returns an empty array if the outbox has never been written or is corrupt.
    public func readAll() -> [PendingExtensionItem] {
        guard let data = defaults.data(forKey: Self.outboxKey) else { return [] }
        return (try? JSONDecoder().decode([PendingExtensionItem].self, from: data)) ?? []
    }

    /// Removes all items from the outbox.
    ///
    /// Call after successfully processing the items returned by ``readAll()``.
    public func clear() {
        defaults.removeObject(forKey: Self.outboxKey)
    }

    // MARK: - Private

    private func store(_ items: [PendingExtensionItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.outboxKey)
    }
}
