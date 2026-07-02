/// A real-world example illustrating the chapter's core concept.
///
/// `scenario` and `whyItMatters` are `String | ToneKeyed` (older chapters use
/// plain strings; newer v2.1 chapters use tone-keyed maps).
/// `whatToDo` is `[String] | ToneKeyed`.
public struct Example: Codable, Sendable {
    public let exampleId: String?
    public let title: String?
    public let scenario: StringOrTone
    public let whatToDo: StringsOrTone
    public let whyItMatters: StringOrTone
    public let contexts: [String]?
    public let category: String?
}
