import Foundation
import CoreKit

/// A fully-resolved navigation target: a tab plus (optionally) a route to push.
///
/// `DeepLinkParser` produces one of these from a URL/`DeepLink`; ``TabRouter``
/// consumes it in `apply(_:)`. Keeping it a plain, `Equatable` value makes the
/// URL → target mapping trivially unit-testable without any SwiftUI.
public enum DeepLinkTarget: Equatable, Sendable {
    /// Switch to a tab's root, pushing nothing.
    case tabRoot(Tab)
    case home(HomeRoute)
    case library(LibraryRoute)
    case reviews(ReviewsRoute)
    case profile(ProfileRoute)
    case settings(SettingsRoute)
}

/// Maps incoming URLs (custom-scheme deep links, `https` universal links) and
/// `NSUserActivity` web URLs onto ``DeepLinkTarget``s.
///
/// The scheme-level URL → ``CoreKit/DeepLink`` parsing already lives in
/// `CoreKit`; this parser adds two things on top: universal-link (`https`)
/// support by reusing the same segment grammar, and the `DeepLink` → tab/route
/// mapping the shell actually navigates with.
public enum DeepLinkParser {
    /// Resolves any incoming URL to a target, or `nil` if it isn't ours or maps
    /// to nothing navigable.
    public static func target(for url: URL) -> DeepLinkTarget? {
        guard let link = deepLink(from: url) else { return nil }
        return target(for: link)
    }

    /// Maps a parsed `DeepLink` onto a navigation target.
    public static func target(for link: DeepLink) -> DeepLinkTarget? {
        switch link {
        case .book(let id):
            return .library(.book(id: id))
        case .chapter(let bookId, let chapter):
            return .library(.chapter(bookId: bookId, chapter: chapter))
        case .pairAccept(let code):
            return .profile(.pairAccept(code: code))
        case .gift(let code):
            return .profile(.gift(code: code))
        case .review:
            return .tabRoot(.reviews)
        case .unknown:
            return nil
        }
    }

    /// Normalizes a URL into a `CoreKit.DeepLink`, accepting both the custom
    /// `chapterflow://` scheme and `https`/`http` universal links that share the
    /// same path grammar (e.g. `https://chapterflow.app/book/42/chapter/3`).
    static func deepLink(from url: URL) -> DeepLink? {
        // Custom scheme: CoreKit already knows how to parse it.
        if let link = DeepLink(url: url) { return link }

        // Universal link: drop the domain host and rebuild a custom-scheme URL
        // from the path segments, then reuse the same parser.
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard !segments.isEmpty,
              let rebuilt = URL(string: "\(DeepLink.scheme)://\(segments.joined(separator: "/"))")
        else {
            return nil
        }
        return DeepLink(url: rebuilt)
    }
}
