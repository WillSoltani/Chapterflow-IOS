import SwiftUI

/// The five-tab shell. Each tab is a `NavigationStack` bound to its own path in
/// the shared ``TabRouter``, with a `navigationDestination` that renders that
/// tab's route enum. Placeholder screens stand in for real features until their
/// packages land.
struct MainTabView: View {
    @Environment(TabRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.homePath) {
                PlaceholderScreen(tab: .home)
                    .navigationDestination(for: HomeRoute.self) { HomeRouteView(route: $0) }
            }
            .tabItem { Label(Tab.home.title, systemImage: Tab.home.systemImage) }
            .tag(Tab.home)

            NavigationStack(path: $router.libraryPath) {
                PlaceholderScreen(tab: .library)
                    .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
            }
            .tabItem { Label(Tab.library.title, systemImage: Tab.library.systemImage) }
            .tag(Tab.library)

            NavigationStack(path: $router.reviewsPath) {
                PlaceholderScreen(tab: .reviews)
                    .navigationDestination(for: ReviewsRoute.self) { ReviewsRouteView(route: $0) }
            }
            .tabItem { Label(Tab.reviews.title, systemImage: Tab.reviews.systemImage) }
            .tag(Tab.reviews)

            NavigationStack(path: $router.profilePath) {
                PlaceholderScreen(tab: .profile)
                    .navigationDestination(for: ProfileRoute.self) { ProfileRouteView(route: $0) }
            }
            .tabItem { Label(Tab.profile.title, systemImage: Tab.profile.systemImage) }
            .tag(Tab.profile)

            NavigationStack(path: $router.settingsPath) {
                PlaceholderScreen(tab: .settings)
                    .navigationDestination(for: SettingsRoute.self) { SettingsRouteView(route: $0) }
            }
            .tabItem { Label(Tab.settings.title, systemImage: Tab.settings.systemImage) }
            .tag(Tab.settings)
        }
    }
}

#Preview("Main tab shell") {
    MainTabView()
        .environment(TabRouter())
        .environment(ToastPresenter())
        .environment(\.dependencies, .mock())
}
