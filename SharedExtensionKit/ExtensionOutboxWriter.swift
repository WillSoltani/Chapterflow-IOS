import Foundation

// MARK: - ExtensionOutboxWriter
//
// Lightweight outbox writer that mirrors Persistence/ExtensionOutbox.swift.
// Extensions cannot link the Persistence SPM package directly, so this file
// duplicates only the write path. The struct name and JSON keys MUST stay in
// sync with their counterparts in the Persistence package.

/// The App Group container identifier shared with the main app.
private let appGroupIdentifier = "group.com.chapterflow"

/// UserDefaults key — must match ExtensionOutbox.outboxKey in Persistence.
private let outboxKey = "extension.outbox"

// MARK: - Item model (mirrors Persistence.PendingExtensionItem)

/// A saved item from the Share or Action extension.
///
/// Mirrors `Persistence.PendingExtensionItem` — JSON representation must be
/// identical so the main app can decode this with its own `PendingExtensionItem` type.
struct ExtensionItem: Codable {
    enum Kind: String, Codable {
        case text
        case link
        case askQuery
    }
    var id: String
    var kind: Kind
    var text: String
    var userNote: String?
    var sourceTitle: String?
    var sourceURL: String?
    var createdAt: Date
}

// MARK: - Writer

/// Appends an ``ExtensionItem`` to the App Group outbox.
///
/// The main app's `ExtensionOutbox.readAll()` method decodes these items on the
/// next foreground activation.
func writeToOutbox(_ item: ExtensionItem) {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

    var items: [ExtensionItem] = []
    if let data = defaults.data(forKey: outboxKey),
       let existing = try? JSONDecoder().decode([ExtensionItem].self, from: data) {
        items = existing
    }
    items.append(item)

    if let encoded = try? JSONEncoder().encode(items) {
        defaults.set(encoded, forKey: outboxKey)
    }
}
