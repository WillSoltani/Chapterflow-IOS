import SwiftUI
import CoreKit

// Bring every workspace module into the composition root so the dependency
// graph is exercised and their public surfaces are reachable as features land.
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

/// The app's public entry point.
///
/// Builds the live ``Dependencies`` once, injects them into the environment, and
/// hosts ``RootView`` (splash → auth/shell). The app target links only
/// `AppFeature` and renders `AppRootView()`.
public struct AppRootView: View {
    @State private var dependencies: Dependencies

    public init() {
        _dependencies = State(initialValue: .live())
    }

    /// Testable/preview seam: inject a specific container.
    init(dependencies: Dependencies) {
        _dependencies = State(initialValue: dependencies)
    }

    public var body: some View {
        RootView()
            .environment(\.dependencies, dependencies)
    }
}

#Preview("Shell (signed in)") {
    AppRootView(dependencies: .mock(signedIn: true))
}

#Preview("Signed out") {
    AppRootView(dependencies: .mock(signedIn: false))
}
