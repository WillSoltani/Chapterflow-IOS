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

    public init(
        chapterId: String,
        number: Int,
        title: String,
        readingTimeMinutes: Int,
        activeVariant: VariantKey,
        availableVariants: [VariantKey],
        content: ChapterVariantContent,
        contentVariants: [String: ChapterVariantContent],
        examples: [Example],
        implementationPlan: ImplementationPlan? = nil,
        reviewCards: [ReviewCard]? = nil,
        keyTakeawayCard: ToneKeyed? = nil,
        v21Extras: V21ChapterExtras? = nil
    ) {
        self.chapterId = chapterId
        self.number = number
        self.title = title
        self.readingTimeMinutes = readingTimeMinutes
        self.activeVariant = activeVariant
        self.availableVariants = availableVariants
        self.content = content
        self.contentVariants = contentVariants
        self.examples = examples
        self.implementationPlan = implementationPlan
        self.reviewCards = reviewCards
        self.keyTakeawayCard = keyTakeawayCard
        self.v21Extras = v21Extras
    }

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // The deployed route emits the canonical shape, but individual keys can be
    // dropped by the serializer when a book/package lacks them (`undefined` is
    // omitted from JSON). Only `chapterId` (identity) and SOME content are
    // required; everything else defaults so a partial chapter renders instead
    // of failing the reader. A chapter with no content at all still throws —
    // there is nothing to render.

    private enum WireKeys: String, CodingKey {
        case chapterId, id
        case number, title
        case readingTimeMinutes, minutes
        case activeVariant, availableVariants, content, contentVariants
        case examples, implementationPlan, reviewCards, keyTakeawayCard, v21Extras
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        chapterId = try c.decodeRequiredFirst(String.self, keys: [.chapterId, .id])
        number = c.decodeFirst(Int.self, keys: [.number]) ?? 0
        title = c.decodeFirst(String.self, keys: [.title]) ?? ""
        readingTimeMinutes = c.decodeFirst(Int.self, keys: [.readingTimeMinutes, .minutes]) ?? 0
        let variants =
            c.decodeFirst([String: ChapterVariantContent].self, keys: [.contentVariants]) ?? [:]
        contentVariants = variants
        let active = c.decodeFirst(VariantKey.self, keys: [.activeVariant])
            ?? variants.keys.sorted().first.map(VariantKey.init(rawValue:))
            ?? .unknown("")
        activeVariant = active
        availableVariants = c.decodeFirst([VariantKey].self, keys: [.availableVariants])
            ?? variants.keys.sorted().map(VariantKey.init(rawValue:))
        guard
            let resolvedContent = c.decodeFirst(ChapterVariantContent.self, keys: [.content])
                ?? variants[active.rawValue]
                // Deterministic fallback: dictionary order is undefined, so
                // pick the lowest-sorted variant key (red-team finding).
                ?? variants.sorted(by: { $0.key < $1.key }).first?.value
        else {
            throw DecodingError.keyNotFound(
                WireKeys.content,
                DecodingError.Context(
                    codingPath: c.codingPath,
                    debugDescription: "Chapter has neither `content` nor any `contentVariants`."))
        }
        content = resolvedContent
        examples = (try? c.decodeLossy(Example.self, forKey: .examples)) ?? []
        implementationPlan = c.decodeFirst(ImplementationPlan.self, keys: [.implementationPlan])
        reviewCards = try? c.decodeLossy(ReviewCard.self, forKey: .reviewCards)
        keyTakeawayCard = c.decodeFirst(ToneKeyed.self, keys: [.keyTakeawayCard])
        v21Extras = c.decodeFirst(V21ChapterExtras.self, keys: [.v21Extras])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(chapterId, forKey: .chapterId)
        try c.encode(number, forKey: .number)
        try c.encode(title, forKey: .title)
        try c.encode(readingTimeMinutes, forKey: .readingTimeMinutes)
        try c.encode(activeVariant, forKey: .activeVariant)
        try c.encode(availableVariants, forKey: .availableVariants)
        try c.encode(content, forKey: .content)
        try c.encode(contentVariants, forKey: .contentVariants)
        try c.encode(examples, forKey: .examples)
        try c.encodeIfPresent(implementationPlan, forKey: .implementationPlan)
        try c.encodeIfPresent(reviewCards, forKey: .reviewCards)
        try c.encodeIfPresent(keyTakeawayCard, forKey: .keyTakeawayCard)
        try c.encodeIfPresent(v21Extras, forKey: .v21Extras)
    }

    // MARK: - Typed access

    /// Returns the content for `key`, falling back to `activeVariant` content,
    /// then to `content`.
    public func variantContent(for key: VariantKey) -> ChapterVariantContent {
        contentVariants[key.rawValue]
            ?? contentVariants[activeVariant.rawValue]
            ?? content
    }

    /// The typed `contentVariants` map (unrecognised variant keys are silently dropped).
    public var typedContentVariants: [VariantKey: ChapterVariantContent] {
        Dictionary(
            uniqueKeysWithValues: contentVariants.compactMap { k, v in
                let key = VariantKey(rawValue: k)
                // Drop future server variants we don't know about from this typed view;
                // they remain accessible via the raw `contentVariants` dict.
                if case .unknown = key { return nil }
                return (key, v)
            }
        )
    }
}
