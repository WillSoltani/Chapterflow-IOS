#if DEBUG
import SwiftUI
import CoreKit

// MARK: - Shake detector

/// Receives UIKit motion events and publishes a shake notification.
///
/// Installed as the key window's first responder so it intercepts motionEnded
/// before any other responder in the chain.
#if canImport(UIKit)
import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("com.chapterflow.deviceDidShake")
}

final class ShakeWindow: UIWindow {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
#endif

// MARK: - Debug menu view

/// A developer debug panel opened by shaking the device (non-release builds only).
///
/// Shows:
/// - Analytics buffer counts (in-memory + disk)
/// - Session / auth state
/// - App version and build number
struct DebugMenuView: View {

    let model: AppModel
    @State private var analyticsBuffered: Int = 0
    @State private var analyticsDisk: Int = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                analyticsSection
                sessionSection
                appInfoSection
            }
            .navigationTitle("Debug Menu")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await refreshAnalyticsCounts() }
    }

    // MARK: - Sections

    private var analyticsSection: some View {
        Section("Analytics") {
            LabeledContent("Buffered (memory)", value: "\(analyticsBuffered)")
            LabeledContent("Queued (disk)", value: "\(analyticsDisk)")
            Button("Flush now") {
                Task { await model.analytics.flush() }
            }
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            LabeledContent("Auth state", value: authStateLabel)
        }
    }

    private var appInfoSection: some View {
        Section("App") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
        }
    }

    // MARK: - Helpers

    private var authStateLabel: String {
        switch model.session.authState {
        case .unknown:        return "Unknown"
        case .signedOut:      return "Signed out"
        case .signedIn:       return "Signed in"
        case .reauthRequired: return "Reauth required"
        case .reconnecting:   return "Reconnecting"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private func refreshAnalyticsCounts() async {
        guard let defaultClient = model.analytics as? DefaultAnalyticsClient else { return }
        analyticsBuffered = await defaultClient.bufferedCount
        analyticsDisk = await defaultClient.diskQueueCount()
    }
}

// MARK: - Shake modifier

/// Listens for the device-shake notification and presents the debug menu.
struct ShakeToDebugModifier: ViewModifier {
    let model: AppModel
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                DebugMenuView(model: model)
            }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                isPresented = true
            }
            #endif
    }
}

extension View {
    /// Attaches the shake-to-open debug menu. Compiled out in release builds.
    func shakeToDebug(model: AppModel) -> some View {
        modifier(ShakeToDebugModifier(model: model))
    }
}
#endif
