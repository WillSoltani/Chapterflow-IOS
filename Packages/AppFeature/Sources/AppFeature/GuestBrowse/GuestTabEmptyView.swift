import SwiftUI
import DesignSystem

/// Friendly signed-out empty state shown on account-only tabs (Reviews, Profile)
/// when the user is browsing as a guest.
struct GuestTabEmptyView: View {
    let systemImage: String
    let title: String
    let description: String
    let onCreateAccount: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            Button("Create Free Account", action: onCreateAccount)
                .buttonStyle(.borderedProminent)
                .tint(Color.cfAccent)
                .accessibilityLabel("Create a free ChapterFlow account")
        }
    }
}

// MARK: - Guest affordance pill

/// A calm, persistent "Create free account" prompt shown above the tab bar
/// while browsing as a guest. Tapping it opens the auth gate.
struct GuestAffordancePill: View {
    let onCreateAccount: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: onCreateAccount) {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.cfSubheadline)
                Text("Create free account")
                    .font(.cfSubheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.cfCaption2)
            }
            .foregroundStyle(Color.cfLabel)
            .padding(.horizontal, .cfSpacing20)
            .padding(.vertical, .cfSpacing12)
            .background(pillBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, .cfSpacing8)
        .accessibilityLabel("Create a free ChapterFlow account")
        .accessibilityHint("Tap to sign up and unlock all features")
    }

    private var pillBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Guest tab empty — Reviews") {
    NavigationStack {
        GuestTabEmptyView(
            systemImage: "star",
            title: "Reviews",
            description: "Create a free account to access your spaced-repetition reviews.",
            onCreateAccount: {}
        )
        .navigationTitle("Reviews")
    }
}

#Preview("Guest tab empty — Profile") {
    NavigationStack {
        GuestTabEmptyView(
            systemImage: "person.crop.circle",
            title: "Profile",
            description: "Create a free account to set up your profile and track your progress.",
            onCreateAccount: {}
        )
        .navigationTitle("Profile")
    }
}

#Preview("Guest affordance pill") {
    GuestAffordancePill(onCreateAccount: {})
        .padding()
}

#Preview("Guest affordance pill — dark") {
    GuestAffordancePill(onCreateAccount: {})
        .padding()
        .preferredColorScheme(.dark)
}
#endif
