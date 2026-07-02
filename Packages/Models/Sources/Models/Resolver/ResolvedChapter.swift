/// A fully-resolved, display-ready chapter with all tone-keyed fields collapsed
/// to single strings for the user's active tone and variant preferences.
///
/// Create one via `ChapterContentResolver.resolve(chapter:selectedVariant:selectedTone:)`.
/// The reader renders exclusively from this type — raw `ToneKeyed` values never reach views.
public struct ResolvedChapter: Sendable {
    // MARK: - Metadata
    public let chapterId: String
    public let number: Int
    public let title: String
    public let readingTimeMinutes: Int

    // MARK: - Resolved content
    public let chapterBreakdown: String?
    public let keyTakeaways: [ResolvedKeyTakeaway]
    public let oneMinuteRecap: ResolvedOneMinuteRecap?
    public let activationPrompt: String?
    public let selfCheckPrompts: [String]
    public let reflectionPrompts: [String]
    public let importantSummary: String?
    public let summaryBullets: [String]
    public let takeaways: [String]
    public let practice: [String]

    // MARK: - Resolved examples
    public let examples: [ResolvedExample]

    // MARK: - Resolved implementation plan
    public let implementationPlan: ResolvedImplementationPlan?

    // MARK: - v21 extras (plain strings — no tone resolution needed)
    public let v21Extras: V21ChapterExtras?

    // MARK: - Resolved review / takeaway cards
    public let reviewCards: [ResolvedReviewCard]
    public let keyTakeawayCard: String?

    // MARK: - Resolution provenance (useful for debugging / analytics)
    public let resolvedVariant: VariantKey
    public let resolvedTone: ToneKey

    public init(
        chapterId: String,
        number: Int,
        title: String,
        readingTimeMinutes: Int,
        chapterBreakdown: String?,
        keyTakeaways: [ResolvedKeyTakeaway],
        oneMinuteRecap: ResolvedOneMinuteRecap?,
        activationPrompt: String?,
        selfCheckPrompts: [String],
        reflectionPrompts: [String],
        importantSummary: String?,
        summaryBullets: [String],
        takeaways: [String],
        practice: [String],
        examples: [ResolvedExample],
        implementationPlan: ResolvedImplementationPlan?,
        v21Extras: V21ChapterExtras?,
        reviewCards: [ResolvedReviewCard],
        keyTakeawayCard: String?,
        resolvedVariant: VariantKey,
        resolvedTone: ToneKey
    ) {
        self.chapterId = chapterId
        self.number = number
        self.title = title
        self.readingTimeMinutes = readingTimeMinutes
        self.chapterBreakdown = chapterBreakdown
        self.keyTakeaways = keyTakeaways
        self.oneMinuteRecap = oneMinuteRecap
        self.activationPrompt = activationPrompt
        self.selfCheckPrompts = selfCheckPrompts
        self.reflectionPrompts = reflectionPrompts
        self.importantSummary = importantSummary
        self.summaryBullets = summaryBullets
        self.takeaways = takeaways
        self.practice = practice
        self.examples = examples
        self.implementationPlan = implementationPlan
        self.v21Extras = v21Extras
        self.reviewCards = reviewCards
        self.keyTakeawayCard = keyTakeawayCard
        self.resolvedVariant = resolvedVariant
        self.resolvedTone = resolvedTone
    }
}

// MARK: - Component types

/// A key-takeaway with tone-keyed fields resolved to strings.
public struct ResolvedKeyTakeaway: Sendable, Equatable {
    public let point: String
    public let moreDetails: String?

    public init(point: String, moreDetails: String?) {
        self.point = point
        self.moreDetails = moreDetails
    }
}

/// An example with all union/tone fields resolved to plain strings.
public struct ResolvedExample: Sendable {
    public let exampleId: String?
    public let title: String?
    public let scenario: String
    /// The "what to do" steps as an array in all cases.
    public let whatToDo: [String]
    public let whyItMatters: String
    public let contexts: [String]
    public let category: String?

    public init(
        exampleId: String?,
        title: String?,
        scenario: String,
        whatToDo: [String],
        whyItMatters: String,
        contexts: [String],
        category: String?
    ) {
        self.exampleId = exampleId
        self.title = title
        self.scenario = scenario
        self.whatToDo = whatToDo
        self.whyItMatters = whyItMatters
        self.contexts = contexts
        self.category = category
    }
}

/// An implementation plan with all tone-keyed fields resolved.
public struct ResolvedImplementationPlan: Sendable {
    public let coreSkill: String?
    public let concreteAction: String?
    public let ifThenPlans: [ResolvedIfThenPlan]
    public let twentyFourHourChallenge: String?
    public let weeklyPractice: String?
    public let friction: String?
    public let checkpoint: String?

    public init(
        coreSkill: String?,
        concreteAction: String?,
        ifThenPlans: [ResolvedIfThenPlan],
        twentyFourHourChallenge: String?,
        weeklyPractice: String?,
        friction: String?,
        checkpoint: String?
    ) {
        self.coreSkill = coreSkill
        self.concreteAction = concreteAction
        self.ifThenPlans = ifThenPlans
        self.twentyFourHourChallenge = twentyFourHourChallenge
        self.weeklyPractice = weeklyPractice
        self.friction = friction
        self.checkpoint = checkpoint
    }
}

/// A single if-then plan with the tone-keyed `plan` field resolved.
public struct ResolvedIfThenPlan: Sendable, Equatable {
    public let context: String
    public let plan: String

    public init(context: String, plan: String) {
        self.context = context
        self.plan = plan
    }
}

/// A review card with tone-keyed front/back resolved to strings.
public struct ResolvedReviewCard: Sendable, Equatable {
    public let cardId: String?
    public let front: String
    public let back: String
    public let difficulty: String?

    public init(cardId: String?, front: String, back: String, difficulty: String?) {
        self.cardId = cardId
        self.front = front
        self.back = back
        self.difficulty = difficulty
    }
}
