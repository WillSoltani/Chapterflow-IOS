/// A structured, tone-keyed plan for applying the chapter's concept in real life.
public struct ImplementationPlan: Codable, Sendable {
    public let coreSkill: ToneKeyed?
    public let concreteAction: ToneKeyed?
    public let ifThenPlans: [IfThenPlan]?
    public let twentyFourHourChallenge: ToneKeyed?
    public let weeklyPractice: ToneKeyed?
    public let friction: ToneKeyed?
    public let checkpoint: ToneKeyed?
}

/// A single if-then habit plan within an `ImplementationPlan`.
public struct IfThenPlan: Codable, Sendable {
    public let context: String
    public let plan: ToneKeyed
}
