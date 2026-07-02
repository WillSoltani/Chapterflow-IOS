/// The teaching content for a single depth variant of a chapter.
///
/// All narrative fields are `ToneKeyed` — use `ChapterContentResolver` to
/// collapse them before rendering. Never pass raw `ToneKeyed` values to views.
public struct ChapterVariantContent: Codable, Sendable {
    public let chapterBreakdown: ToneKeyed?
    public let keyTakeaways: [KeyTakeaway]?
    /// Either a simple `ToneKeyed` string or a structured `{retrieve/connect/preview}` map.
    public let oneMinuteRecap: OneMinuteRecap?
    public let activationPrompt: ToneKeyed?
    public let selfCheckPrompts: [ToneKeyed]?
    public let reflectionPrompts: [ToneKeyed]?
    public let importantSummary: String?
    public let summaryBullets: [String]?
    public let takeaways: [String]?
    public let practice: [String]?
}

/// A single key-takeaway within a chapter variant.
public struct KeyTakeaway: Codable, Sendable {
    public let point: ToneKeyed
    public let moreDetails: ToneKeyed?
}
