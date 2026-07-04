/// Public entry point for the OnboardingFeature module.
public enum OnboardingFeature {
    /// The name of this module.
    public static let moduleName = "OnboardingFeature"
}

// MARK: - Interest categories

/// A selectable interest category shown during onboarding step 2.
public struct InterestCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let systemImage: String

    public init(id: String, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// The default curated interest categories shown during onboarding.
public let defaultInterestCategories: [InterestCategory] = [
    InterestCategory(id: "business", title: "Business", systemImage: "briefcase"),
    InterestCategory(id: "psychology", title: "Psychology", systemImage: "brain.head.profile"),
    InterestCategory(id: "science", title: "Science", systemImage: "atom"),
    InterestCategory(id: "history", title: "History", systemImage: "scroll"),
    InterestCategory(id: "philosophy", title: "Philosophy", systemImage: "quote.bubble"),
    InterestCategory(id: "technology", title: "Technology", systemImage: "laptopcomputer"),
    InterestCategory(id: "self-help", title: "Self-Help", systemImage: "figure.mind.and.body"),
    InterestCategory(id: "biography", title: "Biography", systemImage: "person.text.rectangle"),
    InterestCategory(id: "productivity", title: "Productivity", systemImage: "target"),
    InterestCategory(id: "health", title: "Health", systemImage: "heart"),
    InterestCategory(id: "leadership", title: "Leadership", systemImage: "person.2"),
    InterestCategory(id: "creativity", title: "Creativity", systemImage: "paintbrush"),
]
