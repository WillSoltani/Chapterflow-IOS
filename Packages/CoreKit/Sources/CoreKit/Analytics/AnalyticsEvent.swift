import Foundation

/// A typed analytics event covering the app's key funnels.
///
/// Each case maps to a stable snake_case `name` sent to the backend, plus a set
/// of string `properties`. Keeping this an enum (rather than free-form strings)
/// means the funnel is defined in one place and is impossible to typo at a call
/// site. Use `.custom` sparingly for one-off events not worth a dedicated case.
public enum AnalyticsEvent: Sendable, Equatable {
    case appOpen
    case signIn(method: String)
    case signOut
    case onboardingStep(index: Int)
    case bookStarted(bookId: String)
    case chapterOpened(bookId: String, chapter: Int)
    case chapterCompleted(bookId: String, chapter: Int)
    case quizStarted(bookId: String, chapter: Int)
    case quizSubmitted(bookId: String, chapter: Int, score: Int)
    case paywallViewed(source: String)
    case purchase(productId: String)
    case referralShared
    case custom(name: String, properties: [String: String])

    /// The stable wire name for this event.
    public var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .signIn: return "sign_in"
        case .signOut: return "sign_out"
        case .onboardingStep: return "onboarding_step"
        case .bookStarted: return "book_started"
        case .chapterOpened: return "chapter_opened"
        case .chapterCompleted: return "chapter_completed"
        case .quizStarted: return "quiz_started"
        case .quizSubmitted: return "quiz_submitted"
        case .paywallViewed: return "paywall_viewed"
        case .purchase: return "purchase"
        case .referralShared: return "referral_shared"
        case .custom(let name, _): return name
        }
    }

    /// The event's properties, as a flat string dictionary suitable for JSON.
    public var properties: [String: String] {
        switch self {
        case .appOpen, .signOut, .referralShared:
            return [:]
        case .signIn(let method):
            return ["method": method]
        case .onboardingStep(let index):
            return ["index": String(index)]
        case .bookStarted(let bookId):
            return ["bookId": bookId]
        case .chapterOpened(let bookId, let chapter),
             .chapterCompleted(let bookId, let chapter),
             .quizStarted(let bookId, let chapter):
            return ["bookId": bookId, "chapter": String(chapter)]
        case .quizSubmitted(let bookId, let chapter, let score):
            return ["bookId": bookId, "chapter": String(chapter), "score": String(score)]
        case .paywallViewed(let source):
            return ["source": source]
        case .purchase(let productId):
            return ["productId": productId]
        case .custom(_, let properties):
            return properties
        }
    }
}
