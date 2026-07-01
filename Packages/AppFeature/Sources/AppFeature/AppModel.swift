import SwiftUI
import CoreKit
import AuthKit

/// The top-level observable app state that drives `AppRootView`.
///
/// Responsibilities:
/// - Own the `SessionManager` (auth state + token lifecycle).
/// - Own the currently selected tab.
/// - Own a `Router` per tab so each tab's navigation stack is preserved when
///   the user switches away and back.
/// - Parse incoming deep-link URLs and route them to the correct tab.
@Observable
@MainActor
public final class AppModel {

    // MARK: Session

    public let session: SessionManager

    // MARK: Tab selection

    public var selectedTab: AppTab = .home

    // MARK: Per-tab routers

    public let homeRouter     = Router()
    public let libraryRouter  = Router()
    public let reviewsRouter  = Router()
    public let profileRouter  = Router()
    public let settingsRouter = Router()

    public init(session: SessionManager = SessionManager()) {
        self.session = session
    }

    // MARK: Deep-link handling

    /// Parses `url` and routes to the matching tab/screen.
    /// Silently ignores URLs whose scheme isn't `chapterflow://`.
    public func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        handle(deepLink: link)
    }

    /// Routes a parsed `DeepLink` to the appropriate tab and, where possible,
    /// pushes the matching destination onto that tab's navigation stack.
    public func handle(deepLink: DeepLink) {
        switch deepLink {
        case .book, .chapter:
            selectedTab = .library

        case .review:
            selectedTab = .reviews

        case .pairAccept, .gift:
            selectedTab = .profile

        case .unknown:
            break
        }
        // Feature-level navigation will be wired as modules are built in Phase 2+.
    }
}
