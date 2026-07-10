import SwiftUI
import SettingsFeature

// MARK: - What's New launch gate (P10.9)

/// Auto-presents the What's New screen once after an app update.
///
/// Self-contained: it owns its ``WhatsNewModel`` and presentation state so the
/// app-launch flow in `AppRootView` only gains a single modifier call (the
/// launch hook is deliberately minimal — a sibling PR also touches this flow).
///
/// The show-once decision is delegated to the pure `WhatsNewPolicy`: it presents
/// only after an update (last-seen version older than the current one) and only
/// once first-run onboarding is complete. In every case it records the current
/// version, so a fresh install is captured without showing anything.
private struct WhatsNewLaunchGate: ViewModifier {
    let onboardingCompleted: Bool

    @State private var model = WhatsNewModel()
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let release = model.displayRelease {
                    WhatsNewView(release: release)
                }
            }
            .task {
                guard onboardingCompleted else { return }
                if model.shouldPresentOnLaunch {
                    isPresented = true
                }
                model.markCurrentVersionSeen()
            }
    }
}

extension View {
    /// Presents What's New once after an app update. See ``WhatsNewLaunchGate``.
    func whatsNewLaunchGate(onboardingCompleted: Bool) -> some View {
        modifier(WhatsNewLaunchGate(onboardingCompleted: onboardingCompleted))
    }
}
