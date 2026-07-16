import Foundation

/// A parsed representation of an incoming deep link or universal-link URL.
///
/// Supports both the `chapterflow://` custom scheme **and** Universal Links
/// from the two live domains (`chapterflow.ca` and `app.chapterflow.ca`):
///
/// | Custom scheme                          | Universal Link                                     |
/// |----------------------------------------|----------------------------------------------------|
/// | `chapterflow://book/{id}`              | `https://app.chapterflow.ca/book/{id}`             |
/// | `chapterflow://book/{id}/chapter/{n}`  | `https://app.chapterflow.ca/book/{id}/chapter/{n}` |
/// | `chapterflow://pair/accept/{code}`     | `https://app.chapterflow.ca/pair/accept/{code}`    |
/// | `chapterflow://gift/{code}`            | `https://app.chapterflow.ca/gift/{code}`           |
/// | `chapterflow://ref/{code}`             | `https://app.chapterflow.ca/ref/{code}`            |
/// | `chapterflow://review`                 | `https://app.chapterflow.ca/review`                |
/// | `chapterflow://paywall`                | `https://app.chapterflow.ca/paywall`               |
/// | `chapterflow://journey/{id}`           | `https://app.chapterflow.ca/journey/{id}`          |
/// | `chapterflow://event/{id}`             | `https://app.chapterflow.ca/event/{id}`            |
/// | `chapterflow://library`                | `https://app.chapterflow.ca/library`               |
/// | `chapterflow://profile[/*]`            | `https://app.chapterflow.ca/profile[/*]`           |
/// | `chapterflow://engagement`             | `https://app.chapterflow.ca/engagement`            |
/// | `chapterflow://notifications`          | `https://app.chapterflow.ca/notifications`         |
///
/// Both `chapterflow.ca` and `app.chapterflow.ca` are accepted so that links
/// from either origin open the app. Both domains need `applinks:` entries in
/// the entitlement **and** an AASA file served by the web team (B7). The
/// `chapterflow://` custom scheme works independently of that deploy.
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

    /// All web domains from which Universal Links are accepted.
    ///
    /// Both `chapterflow.ca` (root / marketing domain) and `app.chapterflow.ca`
    /// (the hosted web app) are included so that links from either origin open
    /// the app correctly. Both must appear in the `com.apple.developer.associated-domains`
    /// entitlement (`applinks:chapterflow.ca` and `applinks:app.chapterflow.ca`).
    public static let universalLinkDomains: Set<String> = [
        "chapterflow.ca",
        "app.chapterflow.ca",
    ]

    /// The primary web-app domain used when constructing `webpageURL` for Handoff,
    /// so non-iOS devices can continue reading in a browser.
    public static let webAppDomain = "app.chapterflow.ca"

    /// Parses a URL into a `DeepLink`.
    ///
    /// Accepts the `chapterflow://` custom-scheme links **and** HTTPS Universal
    /// Links on `chapterflow.ca` or `app.chapterflow.ca`.
    /// Returns `nil` for any other URL (wrong scheme or wrong domain).
    public init?(url: URL) {
        let scheme = url.scheme?.lowercased()
        let isCustomScheme = scheme == DeepLink.scheme
        let isUniversalLink = scheme == "https"
            && DeepLink.universalLinkDomains.contains(url.host?.lowercased() ?? "")
        guard isCustomScheme || isUniversalLink else { return nil }
        let segs = DeepLink.segments(from: url, isUniversalLink: isUniversalLink)
        self = DeepLink.parse(segments: segs, url: url)
    }

    // MARK: - Private parsing helpers

    /// Extracts the ordered path segments for routing.
    ///
    /// Custom scheme (`chapterflow://book/abc`): host is the first segment.
    /// Universal Link (`https://app.chapterflow.ca/book/abc`): host is the domain;
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
        case "gift":          return parseExactCode(segments, url: url) { .gift(code: $0) }
        case "ref":           return parseExactCode(segments, url: url) { .referral(code: $0) }
        case "review":        return parseExactFixed(segments, url: url, route: .review)
        case "paywall":       return parseExactFixed(segments, url: url, route: .paywall)
        // Journey/event destination precision belongs to WP-NAV-01B. Preserve
        // their existing safe tab fallback without widening this slice.
        case "journey":       return parseLegacyCode(segments, url: url) { .journey(id: $0) }
        case "event":         return parseLegacyCode(segments, url: url) { .event(id: $0) }
        case "library":       return parseExactFixed(segments, url: url, route: .library)
        case "profile":       return .profile
        case "engagement":    return .engagement
        case "notifications": return parseExactFixed(segments, url: url, route: .notifications)
        default:              return .unknown(url)
        }
    }

    private static func parseBook(segments: [String], url: URL) -> DeepLink {
        guard segments.count >= 2, !segments[1].isEmpty else { return .unknown(url) }
        if segments.count == 2 {
            return .book(id: segments[1])
        }
        guard segments.count == 4,
              segments[2] == "chapter",
              let chapter = Int(segments[3]),
              chapter > 0 else {
            return .unknown(url)
        }
        return .chapter(bookId: segments[1], chapter: chapter)
    }

    private static func parsePair(segments: [String], url: URL) -> DeepLink {
        guard segments.count == 3, segments[1] == "accept", !segments[2].isEmpty else {
            return .unknown(url)
        }
        return .pairAccept(code: segments[2])
    }

    private static func parseExactCode(
        _ segments: [String],
        url: URL,
        make: (String) -> DeepLink
    ) -> DeepLink {
        guard segments.count == 2, !segments[1].isEmpty else { return .unknown(url) }
        return make(segments[1])
    }

    private static func parseExactFixed(
        _ segments: [String],
        url: URL,
        route: DeepLink
    ) -> DeepLink {
        segments.count == 1 ? route : .unknown(url)
    }

    private static func parseLegacyCode(
        _ segments: [String],
        url: URL,
        make: (String) -> DeepLink
    ) -> DeepLink {
        guard segments.count >= 2, !segments[1].isEmpty else { return .unknown(url) }
        return make(segments[1])
    }
}
