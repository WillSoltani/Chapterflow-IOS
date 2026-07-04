import Foundation

/// A parsed representation of an incoming deep link or universal-link URL.
///
/// The concrete mapping of a `DeepLink` onto a tab + route lives in
/// `AppFeature`'s `DeepLinkParser`; `CoreKit` only models the link itself so it
/// can be shared and unit-tested in isolation.
///
/// Supported forms (custom scheme `chapterflow://`):
/// - `chapterflow://book/{id}` → `.book`
/// - `chapterflow://book/{id}/chapter/{n}` → `.chapter`
/// - `chapterflow://pair/accept/{code}` → `.pairAccept`
/// - `chapterflow://gift/{code}` → `.gift`
/// - `chapterflow://ref/{code}` → `.referral`
/// - `chapterflow://review` → `.review`
/// - `chapterflow://library` → `.library`
/// - `chapterflow://profile[/*]` → `.profile`
/// - `chapterflow://engagement` → `.engagement`
/// - `chapterflow://notifications` → `.notifications`
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
    /// Opens the Library tab.
    case library
    /// Opens the Profile tab (social, pairs, engagement).
    case profile
    /// Opens the Home tab at the engagement/progress dashboard.
    case engagement
    /// Opens the notification inbox (P9.4).
    case notifications
    /// A URL we recognize the scheme of but can't map to a known destination.
    case unknown(URL)

    /// The custom URL scheme the app registers.
    public static let scheme = "chapterflow"

    /// Parses a URL into a `DeepLink`. Returns `nil` when the scheme isn't ours.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == DeepLink.scheme else { return nil }
        let segments = DeepLink.segments(from: url)
        self = DeepLink.parse(segments: segments, url: url)
    }

    // MARK: - Private parsing helpers

    private static func segments(from url: URL) -> [String] {
        var result: [String] = []
        if let host = url.host, !host.isEmpty { result.append(host) }
        result.append(contentsOf: url.pathComponents.filter { $0 != "/" && !$0.isEmpty })
        return result
    }

    private static func parse(segments: [String], url: URL) -> DeepLink {
        switch segments.first {
        case "book":        return parseBook(segments: segments, url: url)
        case "pair":        return parsePair(segments: segments, url: url)
        case "gift":        return parseCode(segments, url: url) { .gift(code: $0) }
        case "ref":         return parseCode(segments, url: url) { .referral(code: $0) }
        case "review":      return .review
        case "library":     return .library
        case "profile":     return .profile
        case "engagement":  return .engagement
        case "notifications": return .notifications
        default:            return .unknown(url)
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
