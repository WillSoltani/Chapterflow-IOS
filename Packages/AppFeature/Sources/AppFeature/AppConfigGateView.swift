import SwiftUI
import DesignSystem
import Networking

// MARK: - Gate modifier (single hook)

/// Applies the mobile-config gate over the whole app in one place: a blocking
/// full-cover for the hard-update and maintenance states, and a dismissible top
/// banner for the soft "update available" nudge. Attach once to the root view.
struct AppConfigGateModifier: ViewModifier {
    let service: AppConfigService

    func body(content: Content) -> some View {
        content
            // Blocking states cover everything and cannot be dismissed.
            .overlay {
                switch service.gateState {
                case .hardGate(let message):
                    AppUpdateRequiredView(message: message, appStoreURL: service.appStoreURL)
                        .transition(.opacity)
                case .maintenance(let message):
                    MaintenanceView(message: message)
                        .transition(.opacity)
                case .none, .softNudge:
                    EmptyView()
                }
            }
            // Soft nudge floats at the top and is dismissible.
            .overlay(alignment: .top) {
                if service.shouldShowSoftNudge, case .softNudge(_, let message) = service.gateState {
                    UpdateAvailableNudge(
                        message: message,
                        appStoreURL: service.appStoreURL,
                        onDismiss: { service.dismissSoftNudge() }
                    )
                    .padding(.top, .cfSpacing8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: service.gateState)
    }
}

extension View {
    /// Overlays the force-update / maintenance gate driven by ``AppConfigService``.
    func appConfigGate(_ service: AppConfigService) -> some View {
        modifier(AppConfigGateModifier(service: service))
    }
}

// MARK: - Hard update gate

/// Full-screen, non-dismissible "update required" gate shown when the running
/// build is below `minSupportedVersion`. Its only action is an App Store link.
struct AppUpdateRequiredView: View {
    let message: String?
    let appStoreURL: URL

    var body: some View {
        BlockingGateScaffold(
            systemImage: "arrow.up.circle.fill",
            title: "Update Required",
            message: message ?? "This version of ChapterFlow is no longer supported. Please update to the latest version to continue."
        ) {
            Link(destination: appStoreURL) {
                Text("Update Now")
                    .font(.cfHeadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.cfAccent)
            .accessibilityLabel("Update ChapterFlow on the App Store")
        }
    }
}

// MARK: - Maintenance

/// Full-screen, non-dismissible maintenance screen shown when the backend signals
/// downtime. Offers no navigation — the app is unusable until the server returns.
struct MaintenanceView: View {
    let message: String?

    var body: some View {
        BlockingGateScaffold(
            systemImage: "wrench.and.screwdriver.fill",
            title: "Down for Maintenance",
            message: message ?? "ChapterFlow is temporarily unavailable while we make improvements. Please check back soon."
        )
    }
}

// MARK: - Soft nudge

/// A calm, dismissible banner offering an optional update. Uses a system material
/// (Liquid Glass) capsule consistent with the app's other floating banners.
struct UpdateAvailableNudge: View {
    let message: String?
    let appStoreURL: URL
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: "sparkles")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfAccent)
            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text("Update available")
                    .font(.cfSubheadline.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)
                Text(message ?? "A new version of ChapterFlow is ready.")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .lineLimit(2)
            }
            Spacer(minLength: .cfSpacing8)
            Link("Update", destination: appStoreURL)
                .font(.cfSubheadline.weight(.semibold))
                .foregroundStyle(Color.cfAccent)
                .accessibilityLabel("Update ChapterFlow on the App Store")
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.cfCaption.weight(.semibold))
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update notice")
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing12)
        .background(nudgeBackground, in: RoundedRectangle(cornerRadius: .cfRadius16, style: .continuous))
        .padding(.horizontal, .cfSpacing16)
        .accessibilityElement(children: .contain)
    }

    private var nudgeBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - Shared scaffold

/// The shared layout for the two blocking gates: a centred glyph, title, message,
/// and an optional action. Fills the screen (ignoring safe areas) and intercepts
/// all touches so the underlying app can't be reached.
private struct BlockingGateScaffold<Action: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var action: () -> Action

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder action: @escaping () -> Action = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        ZStack {
            Color.cfBackground.ignoresSafeArea()
            VStack(spacing: .cfSpacing24) {
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color.cfAccent)
                    .accessibilityHidden(true)
                VStack(spacing: .cfSpacing12) {
                    Text(title)
                        .font(.cfTitle1)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.cfLabel)
                    Text(message)
                        .font(.cfBody)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                .padding(.horizontal, .cfSpacing24)
                Spacer()
                action()
                    .padding(.horizontal, .cfSpacing24)
                    .padding(.bottom, .cfSpacing32)
            }
        }
        // Block all interaction with content behind the gate.
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Hard gate — light") {
    AppUpdateRequiredView(message: nil, appStoreURL: URL(string: "https://apps.apple.com")!)
}

#Preview("Hard gate — dark") {
    AppUpdateRequiredView(message: nil, appStoreURL: URL(string: "https://apps.apple.com")!)
        .preferredColorScheme(.dark)
}

#Preview("Hard gate — XXL") {
    AppUpdateRequiredView(
        message: "A critical update is required to keep reading.",
        appStoreURL: URL(string: "https://apps.apple.com")!
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Maintenance — light") {
    MaintenanceView(message: nil)
}

#Preview("Maintenance — dark") {
    MaintenanceView(message: "Back by 3pm ET.")
        .preferredColorScheme(.dark)
}

#Preview("Maintenance — XXL") {
    MaintenanceView(message: nil)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Soft nudge — light") {
    VStack {
        UpdateAvailableNudge(
            message: "Version 2.4 adds offline audio.",
            appStoreURL: URL(string: "https://apps.apple.com")!,
            onDismiss: {}
        )
        Spacer()
    }
    .background(Color.cfGroupedBackground)
}

#Preview("Soft nudge — dark") {
    VStack {
        UpdateAvailableNudge(
            message: nil,
            appStoreURL: URL(string: "https://apps.apple.com")!,
            onDismiss: {}
        )
        Spacer()
    }
    .background(Color.cfGroupedBackground)
    .preferredColorScheme(.dark)
}

#Preview("Soft nudge — XXL") {
    VStack {
        UpdateAvailableNudge(
            message: "A new version of ChapterFlow is ready.",
            appStoreURL: URL(string: "https://apps.apple.com")!,
            onDismiss: {}
        )
        Spacer()
    }
    .background(Color.cfGroupedBackground)
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
