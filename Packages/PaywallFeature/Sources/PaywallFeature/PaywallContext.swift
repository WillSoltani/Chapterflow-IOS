/// The context from which the paywall was presented.
///
/// Used to customise the headline, subtitle, and analytics source so the
/// paywall feels relevant at each entry point rather than generic.
public enum PaywallContext: Sendable, Equatable {
    /// User tapped "Start" on a book they cannot access (out of free slots or no Pro).
    case bookDetail(bookTitle: String)
    /// User hit a Pro-only feature (depth levels, unlimited AI, etc.).
    case lockedFeature(featureName: String)
    /// User navigated to Settings → Subscription → Upgrade.
    case settings

    // MARK: - Display copy

    /// The large bold headline shown at the top of the paywall sheet.
    public var headline: String {
        switch self {
        case .bookDetail(let title):
            return "Unlock \"\(title)\""
        case .lockedFeature(let name):
            return "Unlock \(name)"
        case .settings:
            return "ChapterFlow Pro"
        }
    }

    /// A one-line supporting subtitle under the headline.
    public var subtitle: String {
        switch self {
        case .bookDetail:
            return "Upgrade to read unlimited books and unlock every feature."
        case .lockedFeature:
            return "This feature is available to Pro members."
        case .settings:
            return "Read smarter. Learn more. Own your knowledge."
        }
    }

    /// A snake_case string logged with the `paywall_viewed` analytics event.
    public var analyticsSource: String {
        switch self {
        case .bookDetail:   return "book_detail"
        case .lockedFeature: return "locked_feature"
        case .settings:     return "settings"
        }
    }
}
