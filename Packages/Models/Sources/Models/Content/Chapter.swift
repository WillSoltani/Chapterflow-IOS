/// A fully-loaded chapter, including all depth-variant content.
///
/// Returned by `GET /book/books/{bookId}/chapters/{n}`.
///
/// - `content` is pre-resolved by the server for `activeVariant` (or the `?mode=` param).
/// - `contentVariants` maps raw variant-key strings to their content, enabling
///   instant client-side depth switching without a network round-trip.
///
/// Always resolve via `ChapterContentResolver`; never render raw `ToneKeyed` values.
public struct Chapter: Codable, Sendable {
    public let chapterId: String
    public let number: Int
    public let title: String
    public let readingTimeMinutes: Int
    public let activeVariant: VariantKey
    public let availableVariants: [VariantKey]

    /// Server-resolved content for `activeVariant` (or requested `?mode=`).
    public let content: ChapterVariantContent

    /// All variant contents keyed by raw variant string (e.g. `"easy"`, `"medium"`).
    /// Use `variantContent(for:)` for typed access with fallback.
    public let contentVariants: [String: ChapterVariantContent]

    public let examples: [Example]
    public let implementationPlan: ImplementationPlan?
    public let reviewCards: [ReviewCard]?
    public let keyTakeawayCard: ToneKeyed?
    public let v21Extras: V21ChapterExtras?

    // MARK: - Typed access

    /// Returns the content for `key`, falling back to `activeVariant` content,
    /// then to `content`.
    public func variantContent(for key: VariantKey) -> ChapterVariantContent {
        contentVariants[key.rawValue]
            ?? contentVariants[activeVariant.rawValue]
            ?? content
    }

    /// The typed `contentVariants` map (unknown keys are silently dropped).
    public var typedContentVariants: [VariantKey: ChapterVariantContent] {
        Dictionary(
            uniqueKeysWithValues: contentVariants.compactMap { k, v in
                guard let key = VariantKey(rawValue: k) else { return nil }
                return (key, v)
            }
        )
    }
}
