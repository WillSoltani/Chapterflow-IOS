import Foundation

/// Per-book reading preferences persisted to the App Group key-value store.
///
/// Stores the user's depth variant and tone selections for a specific book,
/// so each book remembers its own settings independently of global preferences.
public struct BookReadingPreferences: Codable, Sendable, Equatable {
    /// Raw value of the user's selected `VariantKey` (e.g. `"medium"`, `"balanced"`).
    public var variantKeyRaw: String
    /// Raw value of the user's selected `ToneKey` (e.g. `"gentle"`, `"direct"`).
    public var toneKeyRaw: String

    public init(variantKeyRaw: String, toneKeyRaw: String) {
        self.variantKeyRaw = variantKeyRaw
        self.toneKeyRaw = toneKeyRaw
    }

    /// The `UserDefaults` key for a specific book's reading preferences.
    public static func storageKey(for bookId: String) -> String {
        "reader.bookprefs.v1.\(bookId)"
    }
}
