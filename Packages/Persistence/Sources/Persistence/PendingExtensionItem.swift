import Foundation

/// A lightweight item saved by the Share or Action extension into the App Group outbox.
///
/// The extension writes this to the App Group `UserDefaults` under
/// ``ExtensionOutbox/outboxKey``. The main app reads and clears the outbox on
/// every foreground activation, then processes items (e.g. creating notebook entries).
///
/// **RF4**: Extensions never open the main SwiftData store.  All data passes through
/// this value type in App Group `UserDefaults`.
public struct PendingExtensionItem: Codable, Sendable, Equatable, Identifiable {

    // MARK: - Kind

    public enum Kind: String, Codable, Sendable {
        /// A selected text passage saved as a note or highlight.
        case text
        /// A URL link saved for later reading.
        case link
        /// A text query to be used in the "Ask the Book" AI flow.
        case askQuery
    }

    // MARK: - Properties

    /// Stable UUID string identifier.
    public var id: String
    /// What kind of item this is.
    public var kind: Kind
    /// The primary payload: selected text, URL string, or ask query.
    public var text: String
    /// Optional user-written annotation added inside the extension UI.
    public var userNote: String?
    /// Title of the source page, app, or document, when available.
    public var sourceTitle: String?
    /// Raw URL string of the source, when available.
    public var sourceURL: String?
    /// Timestamp when the item was created.
    public var createdAt: Date

    // MARK: - Init

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        text: String,
        userNote: String? = nil,
        sourceTitle: String? = nil,
        sourceURL: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.userNote = userNote
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.createdAt = createdAt
    }
}
