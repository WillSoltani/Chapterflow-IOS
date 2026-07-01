import SwiftUI

// Placeholder feature roots and route destinations. Real screens from the
// feature packages (LibraryFeature, ReaderFeature, …) replace these in later
// phases; the composition-root plumbing (tabs, stacks, deep links) is what P0.6
// delivers, and these stand-ins let it run end-to-end.

/// A tab's root placeholder. Includes buttons that push each of the tab's routes
/// so navigation can be exercised by hand and in previews.
struct PlaceholderScreen: View {
    let tab: Tab
    @Environment(TabRouter.self) private var router

    var body: some View {
        List {
            Section {
                ContentUnavailableView(
                    tab.title,
                    systemImage: tab.systemImage,
                    description: Text("\(tab.title) is coming soon.")
                )
            }
            if !demoRoutes.isEmpty {
                Section("Try navigation") {
                    ForEach(Array(demoRoutes.enumerated()), id: \.offset) { _, demo in
                        Button(demo.title) { demo.push(router) }
                    }
                }
            }
        }
        .navigationTitle(tab.title)
    }

    /// Sample pushes so each stack can be exercised without real data.
    private var demoRoutes: [(title: String, push: @MainActor (TabRouter) -> Void)] {
        switch tab {
        case .home:
            return [("Continue reading", { $0.homePath.append(HomeRoute.continueReading(bookId: "sample")) })]
        case .library:
            return [
                ("Open a book", { $0.libraryPath.append(LibraryRoute.book(id: "sample")) }),
                ("Open a chapter", { $0.libraryPath.append(LibraryRoute.chapter(bookId: "sample", chapter: 1)) })
            ]
        case .reviews:
            return [("Open a review card", { $0.reviewsPath.append(ReviewsRoute.card(id: "sample")) })]
        case .profile:
            return [("Accept a pair", { $0.profilePath.append(ProfileRoute.pairAccept(code: "ABC123")) })]
        case .settings:
            return [("About", { $0.settingsPath.append(SettingsRoute.about) })]
        }
    }
}

/// A generic destination placeholder used by every route view.
private struct RouteDetail: View {
    let title: String
    let subtitle: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "square.stack.3d.up")
        } description: {
            Text(subtitle)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayModeInline()
    }
}

// One thin view per route enum; switches over the cases so navigation is
// type-safe and the destinations are visible in previews.

struct HomeRouteView: View {
    let route: HomeRoute
    var body: some View {
        switch route {
        case .continueReading(let bookId):
            RouteDetail(title: "Continue Reading", subtitle: "Book \(bookId)")
        }
    }
}

struct LibraryRouteView: View {
    let route: LibraryRoute
    var body: some View {
        switch route {
        case .book(let id):
            RouteDetail(title: "Book", subtitle: "Book \(id)")
        case .chapter(let bookId, let chapter):
            RouteDetail(title: "Reader", subtitle: "Book \(bookId) · Chapter \(chapter)")
        }
    }
}

struct ReviewsRouteView: View {
    let route: ReviewsRoute
    var body: some View {
        switch route {
        case .card(let id):
            RouteDetail(title: "Review Card", subtitle: "Card \(id)")
        }
    }
}

struct ProfileRouteView: View {
    let route: ProfileRoute
    var body: some View {
        switch route {
        case .pairAccept(let code):
            RouteDetail(title: "Accept Pair", subtitle: "Invite code \(code)")
        case .gift(let code):
            RouteDetail(title: "Claim Gift", subtitle: "Gift code \(code)")
        }
    }
}

struct SettingsRouteView: View {
    let route: SettingsRoute
    var body: some View {
        switch route {
        case .about:
            RouteDetail(title: "About", subtitle: "ChapterFlow")
        }
    }
}

// A tiny cross-platform shim: `navigationBarTitleDisplayMode` is iOS-only, but
// the package also builds on the macOS host for `swift test`.
private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
