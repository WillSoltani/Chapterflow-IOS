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

    public init(
        hook: String?,
        counterintuition: String?,
        tryThisNow: String?,
        keyTakeaway: String?,
        memorableLines: [MemorableLine]?,
        experiencePlan: V21ExperiencePlan?
    ) {
        self.hook = hook
        self.counterintuition = counterintuition
        self.tryThisNow = tryThisNow
        self.keyTakeaway = keyTakeaway
        self.memorableLines = memorableLines
        self.experiencePlan = experiencePlan
    }
}

/// A pull-quote-style memorable line from the chapter.
public struct MemorableLine: Codable, Sendable {
    public let text: String
    public let location: String?
    public let why: String?

    public init(text: String, location: String?, why: String?) {
        self.text = text
        self.location = location
        self.why = why
    }
}

/// An interactive experience plan embedded in the reader.
public struct V21ExperiencePlan: Codable, Sendable {
    public let failureRecovery: FailureRecovery?
    public let transferPrompt: TransferPrompt?
    public let behaviorLoop: BehaviorLoop?

    public init(
        failureRecovery: FailureRecovery?,
        transferPrompt: TransferPrompt?,
        behaviorLoop: BehaviorLoop?
    ) {
        self.failureRecovery = failureRecovery
        self.transferPrompt = transferPrompt
        self.behaviorLoop = behaviorLoop
    }
}

/// Prompts that help a reader recover when they can't apply the concept.
public struct FailureRecovery: Codable, Sendable {
    public let normalizingLine: String
    public let cueQuestion: String
    public let options: [String]
    public let repairLine: String

    public init(normalizingLine: String, cueQuestion: String, options: [String], repairLine: String) {
        self.normalizingLine = normalizingLine
        self.cueQuestion = cueQuestion
        self.options = options
        self.repairLine = repairLine
    }
}

/// A prompt encouraging application of the concept in diverse contexts.
public struct TransferPrompt: Codable, Sendable {
    public let prompt: String
    public let contexts: [String]

    public init(prompt: String, contexts: [String]) {
        self.prompt = prompt
        self.contexts = contexts
    }
}

/// A behavior-pattern loop mapping reader archetypes to examples/plans.
public struct BehaviorLoop: Codable, Sendable {
    public let readerPatterns: [ReaderPattern]

    public init(readerPatterns: [ReaderPattern]) {
        self.readerPatterns = readerPatterns
    }
}

/// A reader archetype in a behavior loop.
public struct ReaderPattern: Codable, Sendable {
    public let id: String
    public let label: String
    public let mapsToPlanIndex: Int?
    public let mapsToExampleIndex: Int?

    public init(id: String, label: String, mapsToPlanIndex: Int?, mapsToExampleIndex: Int?) {
        self.id = id
        self.label = label
        self.mapsToPlanIndex = mapsToPlanIndex
        self.mapsToExampleIndex = mapsToExampleIndex
    }
}
