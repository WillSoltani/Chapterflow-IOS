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
    /// A URL we recognize the scheme of but can't map to a known destination.
    case unknown(URL)

    /// The custom URL scheme the app registers.
    public static let scheme = "chapterflow"

    /// Parses a URL into a `DeepLink`. Returns `nil` when the scheme isn't ours.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == DeepLink.scheme else { return nil }

        // Combine host + path into a normalized list of segments, since with a
        // custom scheme the first segment arrives as `host` (e.g. "book").
        var segments: [String] = []
        if let host = url.host, !host.isEmpty {
            segments.append(host)
        }
        segments.append(
            contentsOf: url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        )

        switch segments.first {
        case "book":
            // book/{id} or book/{id}/chapter/{n}
            guard segments.count >= 2, !segments[1].isEmpty else {
                self = .unknown(url); return
            }
            let bookId = segments[1]
            if segments.count >= 4, segments[2] == "chapter", let n = Int(segments[3]) {
                self = .chapter(bookId: bookId, chapter: n)
            } else {
                self = .book(id: bookId)
            }

        case "pair":
            // pair/accept/{code}
            guard segments.count >= 3, segments[1] == "accept", !segments[2].isEmpty else {
                self = .unknown(url); return
            }
            self = .pairAccept(code: segments[2])

        case "gift":
            // gift/{code}
            guard segments.count >= 2, !segments[1].isEmpty else {
                self = .unknown(url); return
            }
            self = .gift(code: segments[1])

        case "ref":
            // ref/{code} — referral invite link
            guard segments.count >= 2, !segments[1].isEmpty else {
                self = .unknown(url); return
            }
            self = .referral(code: segments[1])

        case "review":
            self = .review

        default:
            self = .unknown(url)
        }
    }
}
