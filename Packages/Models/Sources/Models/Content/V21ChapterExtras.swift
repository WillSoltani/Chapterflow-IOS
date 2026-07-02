/// Premium reader-chrome content introduced in the v2.1 content system.
///
/// All fields are optional plain strings — no tone resolution required.
/// These are displayed verbatim in the reader UI.
public struct V21ChapterExtras: Codable, Sendable {
    public let hook: String?
    public let counterintuition: String?
    public let tryThisNow: String?
    public let keyTakeaway: String?
    public let memorableLines: [MemorableLine]?
    public let experiencePlan: V21ExperiencePlan?
}

/// A pull-quote-style memorable line from the chapter.
public struct MemorableLine: Codable, Sendable {
    public let text: String
    public let location: String?
    public let why: String?
}

/// An interactive experience plan embedded in the reader.
public struct V21ExperiencePlan: Codable, Sendable {
    public let failureRecovery: FailureRecovery?
    public let transferPrompt: TransferPrompt?
    public let behaviorLoop: BehaviorLoop?
}

/// Prompts that help a reader recover when they can't apply the concept.
public struct FailureRecovery: Codable, Sendable {
    public let normalizingLine: String
    public let cueQuestion: String
    public let options: [String]
    public let repairLine: String
}

/// A prompt encouraging application of the concept in diverse contexts.
public struct TransferPrompt: Codable, Sendable {
    public let prompt: String
    public let contexts: [String]
}

/// A behavior-pattern loop mapping reader archetypes to examples/plans.
public struct BehaviorLoop: Codable, Sendable {
    public let readerPatterns: [ReaderPattern]
}

/// A reader archetype in a behavior loop.
public struct ReaderPattern: Codable, Sendable {
    public let id: String
    public let label: String
    public let mapsToPlanIndex: Int?
    public let mapsToExampleIndex: Int?
}
