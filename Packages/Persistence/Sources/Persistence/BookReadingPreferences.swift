import Foundation

/// Per-book reading preferences persisted to the App Group key-value store.
///
/// Stores the user's depth variant, tone, learning mode, and audio preference
/// for a specific book, so each book remembers its own settings independently
/// of the global ``AppPreferences``.
///
/// Custom `Codable` decoding applies defaults for fields added after v1
/// so existing stored JSON (which has only `variantKeyRaw` + `toneKeyRaw`)
/// decodes without error.
public struct BookReadingPreferences: Codable, Sendable, Equatable {
    /// Raw value of the user's selected `VariantKey` (e.g. `"medium"`, `"balanced"`).
    public var variantKeyRaw: String
    /// Raw value of the user's selected `ToneKey` (e.g. `"gentle"`, `"direct"`).
    public var toneKeyRaw: String
    /// Raw value of the user's `LearningMode` (e.g. `"reading"`, `"listening"`).
    /// Defaults to `"reading"` when absent in stored JSON.
    public var learningMode: String
    /// Whether audio narration is the default for this book.
    /// Defaults to `false` when absent in stored JSON.
    public var audioNarrationEnabled: Bool

    public init(
        variantKeyRaw: String,
        toneKeyRaw: String,
        learningMode: String = LearningMode.reading.rawValue,
        audioNarrationEnabled: Bool = false
    ) {
        self.variantKeyRaw = variantKeyRaw
        self.toneKeyRaw = toneKeyRaw
        self.learningMode = learningMode
        self.audioNarrationEnabled = audioNarrationEnabled
    }

    // MARK: - Codable (tolerant: new fields default gracefully)

    private enum CodingKeys: String, CodingKey {
        case variantKeyRaw, toneKeyRaw, learningMode, audioNarrationEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variantKeyRaw = try container.decode(String.self, forKey: .variantKeyRaw)
        toneKeyRaw = try container.decode(String.self, forKey: .toneKeyRaw)
        learningMode = (try? container.decode(String.self, forKey: .learningMode))
            ?? LearningMode.reading.rawValue
        audioNarrationEnabled = (try? container.decode(Bool.self, forKey: .audioNarrationEnabled))
            ?? false
    }

    // MARK: - Storage key

    /// The `UserDefaults` key for a specific book's reading preferences.
    public static func storageKey(for bookId: String) -> String {
        "reader.bookprefs.v1.\(bookId)"
    }
}
