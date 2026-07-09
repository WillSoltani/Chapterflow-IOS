import SwiftUI
import DesignSystem

// MARK: - Reconnecting banner

/// A floating glass pill shown when the app is attempting to reconnect.
struct ReconnectingBanner: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: .cfSpacing8) {
            ProgressView().scaleEffect(0.8)
            Text("Reconnecting…").font(.cfFootnote)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
        .background(bannerBackground, in: Capsule())
        .padding(.top, .cfSpacing8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel("Reconnecting to the server")
    }

    private var bannerBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - Reading Focus overlay

/// Full-screen overlay shown over the Profile/social tab when Reading Focus is
/// active. Communicates the suppression clearly and lets the user navigate to
/// reading content without disabling Focus.
struct ReadingFocusOverlayView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let onGoToLibrary: () -> Void

    var body: some View {
        VStack(spacing: .cfSpacing24) {
            Image(systemName: "book.pages")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.cfAccent)
            VStack(spacing: .cfSpacing8) {
                Text("Reading Focus Active")
                    .font(.cfTitle3)
                    .foregroundStyle(Color.cfLabel)
                Text("Social features are hidden while your Focus is on.")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
            }
            Button(action: onGoToLibrary) {
                Label("Go to Library", systemImage: "books.vertical")
                    .font(.cfHeadline)
                    .padding(.horizontal, .cfSpacing24)
                    .padding(.vertical, .cfSpacing12)
                    .background(Color.cfAccent, in: RoundedRectangle(cornerRadius: .cfRadius12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency {
                Color.cfBackground.ignoresSafeArea()
            } else {
                Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading Focus is active. Social features are hidden.")
    }
}

// MARK: - Extension inbox banner

/// A floating confirmation pill shown when the Share or Action extension saved items.
struct ExtensionInboxBanner: View {
    let count: Int
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "square.and.arrow.down")
                .font(.cfCaption.weight(.semibold))
                .foregroundStyle(Color.cfAccent)
            Text(count == 1 ? "1 item saved to Notebook" : "\(count) items saved to Notebook")
                .font(.cfFootnote)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
        .background(bannerBackground, in: Capsule())
        .padding(.top, .cfSpacing8)
        .accessibilityLabel(count == 1 ? "1 item saved to Notebook" : "\(count) items saved to Notebook")
    }

    private var bannerBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - iPad keyboard shortcuts

/// Zero-size, fully transparent button group that registers ⌘1–5 and ⌘F
/// keyboard shortcuts for primary tab navigation on iPad with a hardware
/// keyboard. Hidden from the accessibility tree; purely a key-command hook.
struct IPadKeyboardShortcutsView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        #if os(iOS)
        ZStack {
            Button("Home") { selectedTab = .home }
                .keyboardShortcut("1", modifiers: .command)
            Button("Library") { selectedTab = .library }
                .keyboardShortcut("2", modifiers: .command)
            Button("Reviews") { selectedTab = .reviews }
                .keyboardShortcut("3", modifiers: .command)
            Button("Profile") { selectedTab = .profile }
                .keyboardShortcut("4", modifiers: .command)
            Button("Settings") { selectedTab = .settings }
                .keyboardShortcut("5", modifiers: .command)
            Button("Search") { selectedTab = .library }
                .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
        #else
        EmptyView()
        #endif
    }
}
