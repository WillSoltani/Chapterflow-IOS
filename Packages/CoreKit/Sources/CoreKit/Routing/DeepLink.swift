import Foundation

/// A parsed representation of an incoming deep link or universal-link URL.
///
/// Supports both the `chapterflow://` custom scheme **and**
/// `https://chapterflow.app` Universal Links:
///
/// | Custom scheme                          | Universal Link                                |
/// |----------------------------------------|-----------------------------------------------|
/// | `chapterflow://book/{id}`              | `https://chapterflow.app/book/{id}`           |
/// | `chapterflow://book/{id}/chapter/{n}`  | `https://chapterflow.app/book/{id}/chapter/{n}` |
/// | `chapterflow://pair/accept/{code}`     | `https://chapterflow.app/pair/accept/{code}`  |
/// | `chapterflow://gift/{code}`            | `https://chapterflow.app/gift/{code}`         |
/// | `chapterflow://ref/{code}`             | `https://chapterflow.app/ref/{code}`          |
/// | `chapterflow://review`                 | `https://chapterflow.app/review`              |
/// | `chapterflow://paywall`                | `https://chapterflow.app/paywall`             |
/// | `chapterflow://journey/{id}`           | `https://chapterflow.app/journey/{id}`        |
/// | `chapterflow://event/{id}`             | `https://chapterflow.app/event/{id}`          |
/// | `chapterflow://library`                | `https://chapterflow.app/library`             |
/// | `chapterflow://profile[/*]`            | `https://chapterflow.app/profile[/*]`         |
/// | `chapterflow://engagement`             | `https://chapterflow.app/engagement`          |
/// | `chapterflow://notifications`          | `https://chapterflow.app/notifications`       |
///
/// Universal Links require the `applinks:chapterflow.app` Associated Domain entitlement
/// **and** the AASA file served by the web team (B7). The custom scheme
/// works independently of the web deploy.
///
/// iOS has no deferred deep-link API — a code link that sends a new user
/// through the App Store loses the code. Views that handle code flows
/// (pair/accept, gift, referral) therefore always show a manual "Enter a code"
/// fallback.
public enum DeepLink: Sendable, Equatable {
    case book(id: String)
    case chapter(bookId: String, chapter: Int)
    case pairAccept(code: String)
    case gift(code: String)
    /// A referral invite link. iOS has no deferred deep-link API so an
    /// install-then-open flow cannot carry the code automatically; the app
    /// pre-fills the manual "Enter a code" screen with it instead.
    case referral(code: String)
    case review
    /// Opens the paywall / upgrade screen.
    case paywall
    /// Opens a specific journey by server-assigned ID.
    case journey(id: String)
    /// Opens a specific seasonal event by server-assigned ID.
    case event(id: String)
    /// Opens the Library tab.
    case library
    /// Opens the Profile tab (social, pairs, engagement).
    case profile
    /// Opens the Home tab at the engagement/progress dashboard.
    case engagement
    /// Opens the notification inbox (P9.4).
    case notifications
    /// A URL we recognize the scheme or domain of but can't map to a known destination.
    case unknown(URL)

    /// The custom URL scheme the app registers.
    public static let scheme = "chapterflow"

    /// The web domain that serves Universal Links.
    ///
    /// - Requires `applinks:chapterflow.app` in the app's Associated Domains entitlement.
    /// - Requires an `apple-app-site-association` file served at the root of that domain
    ///   (coordinated with the web team via B7).
    public static let universalLinkDomain = "chapterflow.app"

    /// Parses a URL into a `DeepLink`.
    ///
    /// Accepts both the `chapterflow://` custom-scheme links **and**
    /// `https://chapterflow.app/...` Universal Links.
    /// Returns `nil` for any other URL (wrong scheme or wrong domain).
    public init?(url: URL) {
        let scheme = url.scheme?.lowercased()
        let isCustomScheme = scheme == DeepLink.scheme
        let isUniversalLink = scheme == "https" && url.host?.lowercased() == DeepLink.universalLinkDomain
        guard isCustomScheme || isUniversalLink else { return nil }
        let segs = DeepLink.segments(from: url, isUniversalLink: isUniversalLink)
        self = DeepLink.parse(segments: segs, url: url)
    }

    // MARK: - Private parsing helpers

    /// Extracts the ordered path segments for routing.
    ///
    /// Custom scheme (`chapterflow://book/abc`): host is the first segment.
    /// Universal Link (`https://chapterflow.app/book/abc`): host is the domain;
    /// segments come from path components only.
    private static func segments(from url: URL, isUniversalLink: Bool) -> [String] {
        if isUniversalLink {
            return url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        }
        var result: [String] = []
        if let host = url.host, !host.isEmpty { result.append(host) }
        result.append(contentsOf: url.pathComponents.filter { $0 != "/" && !$0.isEmpty })
        return result
    }

    private static func parse(segments: [String], url: URL) -> DeepLink {
        switch segments.first {
        case "book":          return parseBook(segments: segments, url: url)
        case "pair":          return parsePair(segments: segments, url: url)
        case "gift":          return parseCode(segments, url: url) { .gift(code: $0) }
        case "ref":           return parseCode(segments, url: url) { .referral(code: $0) }
        case "review":        return .review
        case "paywall":       return .paywall
        case "journey":       return parseCode(segments, url: url) { .journey(id: $0) }
        case "event":         return parseCode(segments, url: url) { .event(id: $0) }
        case "library":       return .library
        case "profile":       return .profile
        case "engagement":    return .engagement
        case "notifications": return .notifications
        default:              return .unknown(url)
        }
    }

    private static func parseBook(segments: [String], url: URL) -> DeepLink {
        guard segments.count >= 2, !segments[1].isEmpty else { return .unknown(url) }
        let bookId = segments[1]
        if segments.count >= 4, segments[2] == "chapter", let n = Int(segments[3]) {
            return .chapter(bookId: bookId, chapter: n)
        }
        return .book(id: bookId)
    }

    private static func parsePair(segments: [String], url: URL) -> DeepLink {
        guard segments.count >= 3, segments[1] == "accept", !segments[2].isEmpty else {
            return .unknown(url)
        }
        return .pairAccept(code: segments[2])
    }

    private static func parseCode(_ segments: [String], url: URL, make: (String) -> DeepLink) -> DeepLink {
        guard segments.count >= 2, !segments[1].isEmpty else { return .unknown(url) }
        return make(segments[1])
    }
}
