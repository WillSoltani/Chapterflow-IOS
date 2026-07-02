import Foundation

/// The resolved location of an annotation within a chapter's content.
///
/// Anchored to the (variant, tone) pair that was active when the annotation was made.
/// Survives font-size and theme changes by construction (block index + char offsets
/// are layout-independent). The anchor is validated against current block text at
/// render time — if the text has changed, it degrades to a block-level highlight.
public struct AnnotationAnchor: Codable, Sendable, Equatable, Hashable {
    /// Raw value of the `VariantKey` active when the annotation was made.
    public let variantKey: String
    /// Raw value of the `ToneKey` active when the annotation was made.
    public let toneKey: String
    /// Index of the block within the resolved block array.
    public let blockIndex: Int
    /// Type name of the block (e.g. "paragraph", "bullet", "heading").
    public let blockType: String
    /// Character offset of the selection start within the block's plain text.
    public let startChar: Int
    /// Character offset of the selection end (exclusive) within the block's plain text.
    public let endChar: Int
    /// The exact text that was selected when the annotation was created.
    /// Used to validate the anchor remains correct after content updates.
    public let snippet: String

    public init(
        variantKey: String,
        toneKey: String,
        blockIndex: Int,
        blockType: String,
        startChar: Int,
        endChar: Int,
        snippet: String
    ) {
        self.variantKey = variantKey
        self.toneKey = toneKey
        self.blockIndex = blockIndex
        self.blockType = blockType
        self.startChar = startChar
        self.endChar = endChar
        self.snippet = snippet
    }

    // MARK: - Validation

    /// Validates the anchor against current block text.
    ///
    /// If the character range is in bounds AND the substring matches `snippet`,
    /// returns `self` unchanged. Otherwise degrades to a block-level anchor
    /// (startChar = 0, endChar = blockText.count) so the highlight still renders
    /// without painting at a wrong position.
    public func validated(against blockText: String) -> AnnotationAnchor {
        let len = blockText.count
        guard startChar >= 0, endChar <= len, startChar < endChar else {
            return degraded(to: blockText)
        }
        let startIndex = blockText.index(blockText.startIndex, offsetBy: startChar)
        let endIndex = blockText.index(blockText.startIndex, offsetBy: endChar)
        let current = String(blockText[startIndex..<endIndex])
        return current == snippet ? self : degraded(to: blockText)
    }

    private func degraded(to blockText: String) -> AnnotationAnchor {
        AnnotationAnchor(
            variantKey: variantKey,
            toneKey: toneKey,
            blockIndex: blockIndex,
            blockType: blockType,
            startChar: 0,
            endChar: blockText.count,
            snippet: snippet
        )
    }

    /// Returns `true` when this anchor covers the entire block text.
    public var isBlockLevel: Bool {
        startChar == 0 && endChar == snippet.count
    }

    // MARK: - JSON helpers

    /// Encodes the anchor to a JSON string for storage in `LocalAnnotation.anchorJSON`.
    public func asJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes an anchor from a JSON string stored in `LocalAnnotation.anchorJSON`.
    public static func from(json: String) -> AnnotationAnchor? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AnnotationAnchor.self, from: data)
    }
}
