import SwiftUI
import StoreKit
import CoreKit
import CoreSpotlight
import DesignSystem
import Models
import Networking
import Persistence
import AuthKit
import LibraryFeature
import ReaderFeature
import QuizFeature
import PaywallFeature
import EngagementFeature
import AIFeature
import SocialFeature
import NotificationsFeature
import OnboardingFeature
import SettingsFeature
import SyncEngine

extension AppRootView {
    // MARK: - Guest tab content

    @ViewBuilder
    func guestTabContent(for tab: AppTab) -> some View {
        let authGateClosure: (String, VariantFamily) -> Void = { bookId, variantFamily in
            model.requestAuth(intent: .startBook(bookId: bookId, variantFamily: variantFamily))
        }
        let requireAuthClosure: () -> Void = {
            model.requestAuth(intent: .none)
        }

        switch tab {
        case .home:
            HomeView(
                repository: model.libraryRepository,
                bookDetailRepository: model.bookDetailRepository,
                aiRepository: nil,
                preferences: model.guestPreferences,
                store: model.guestKeyValueStore,
                isGuest: true,
                workPermit: model.workPermit,
                onOpenReader: nil, // guests can't open the reader
                onShowPaywall: nil,
                onRequireAuth: requireAuthClosure,
                onSignInRequired: authGateClosure
            )
        case .library:
            LibraryView(
                repository: model.libraryRepository,
                bookDetailRepository: model.bookDetailRepository,
                aiRepository: nil,
                preferences: model.guestPreferences,
                store: model.guestKeyValueStore,
                isGuest: true,
                workPermit: model.workPermit,
                onOpenReader: nil,
                onShowPaywall: nil,
                onRequireAuth: requireAuthClosure,
                onSignInRequired: authGateClosure
            )
        case .reviews:
            NavigationStack {
                GuestTabEmptyView(
                    systemImage: "star",
                    title: "Reviews",
                    description: "Create a free account to access spaced-repetition reviews.",
                    onCreateAccount: requireAuthClosure
                )
                .navigationTitle("Reviews")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
            }
        case .profile:
            NavigationStack {
                GuestTabEmptyView(
                    systemImage: "person.crop.circle",
                    title: "Profile",
                    description: "Create a free account to track your progress and connect with others.",
                    onCreateAccount: requireAuthClosure
                )
                .navigationTitle("Profile")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
            }
        case .settings:
            NavigationStack {
                GuestTabEmptyView(
                    systemImage: "gearshape",
                    title: "Settings",
                    description: "Create a free account to access settings.",
                    onCreateAccount: requireAuthClosure
                )
                .navigationTitle("Settings")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
            }
        }
    }
}
