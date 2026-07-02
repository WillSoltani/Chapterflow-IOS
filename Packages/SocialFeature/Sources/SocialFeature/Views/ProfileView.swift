import SwiftUI
import Models
import DesignSystem
import CoreKit

/// The authenticated user's own profile tab.
///
/// Shows display name, avatar, tier, engagement stats, equipped cosmetics,
/// a badge preview, and an "Edit Profile" entry point.
public struct ProfileView: View {

    @State private var model: ProfileModel
    @State private var editProfilePresented = false

    public init(repository: any SocialRepository) {
        _model = State(initialValue: ProfileModel(repository: repository))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profile")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .refreshable { await model.load() }
                .sheet(isPresented: $editProfilePresented) {
                    EditProfileView(model: model)
                }
        }
        .task { await model.load() }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle where model.profile == nil,
             .loading where model.profile == nil:
            loadingSkeleton
        case .error(let message):
            errorView(message)
        default:
            if let profile = model.profile {
                loadedScrollView(profile: profile)
            }
        }
    }

    // MARK: - Loaded state

    private func loadedScrollView(profile: OwnProfile) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                profileHeader(profile: profile)
                statsGrid(profile: profile)

                if profile.equippedFrame != nil || profile.equippedTheme != nil {
                    cosmeticsSection(profile: profile)
                }

                if !model.badges.isEmpty || profile.badgeCount > 0 {
                    badgesSection(profile: profile)
                }

                Divider()
                    .padding(.horizontal, .cfSpacing16)

                editRow
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing24)
        }
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Header

    private func profileHeader(profile: OwnProfile) -> some View {
        VStack(spacing: .cfSpacing12) {
            AvatarView(
                avatarUrl: profile.avatarUrl,
                avatarEmoji: profile.avatarEmoji,
                initials: profile.initials,
                equippedFrame: profile.equippedFrame,
                size: 84
            )

            VStack(spacing: .cfSpacing4) {
                Text(profile.displayName ?? "Reader")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)

                tierBadge(profile.tier)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .cfSpacing8)
    }

    private func tierBadge(_ tier: ProfileTier) -> some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: tier.systemImageName)
                .font(.cfCaption)
            Text(tier.displayLabel)
                .font(.cfCaption)
        }
        .foregroundStyle(Color.cfAccent)
        .padding(.horizontal, .cfSpacing12)
        .padding(.vertical, .cfSpacing4)
        .background(Color.cfAccent.opacity(0.12), in: Capsule())
    }

    // MARK: - Stats grid

    private func statsGrid(profile: OwnProfile) -> some View {
        HStack(spacing: .cfSpacing8) {
            ProfileStatItemView(
                icon: "🔥",
                value: "\(profile.currentStreak)",
                label: "Streak"
            )
            ProfileStatItemView(
                icon: "📚",
                value: "\(profile.booksFinished)",
                label: "Books"
            )
            ProfileStatItemView(
                icon: "⚡",
                value: Self.formatPoints(profile.flowPoints),
                label: "Points"
            )
        }
    }

    // MARK: - Cosmetics section

    private func cosmeticsSection(profile: OwnProfile) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Equipped")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: .cfSpacing8) {
                if let frame = profile.equippedFrame {
                    cosmeticRow(
                        label: "Frame",
                        name: frame.name,
                        systemImage: "circle.dashed"
                    )
                }
                if let theme = profile.equippedTheme {
                    cosmeticRow(
                        label: "Theme",
                        name: theme.name,
                        systemImage: "paintpalette"
                    )
                }
            }
            .padding(.cfSpacing16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
        }
    }

    private func cosmeticRow(label: String, name: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(Color.cfAccent)
                .frame(width: .cfIconSmall)
            Text(label)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
            Spacer()
            Text(name)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
        }
    }

    // MARK: - Badges section

    private func badgesSection(profile: OwnProfile) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            HStack {
                Text("Badges")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Spacer()
                Text("\(profile.badgeCount)")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }

            BadgePreviewView(
                badges: model.badges,
                badgeCount: profile.badgeCount
            )
        }
    }

    // MARK: - Edit profile row

    private var editRow: some View {
        Button {
            editProfilePresented = true
        } label: {
            HStack {
                Image(systemName: "pencil")
                    .foregroundStyle(Color.cfAccent)
                    .frame(width: .cfIconSmall)
                Text("Edit Profile")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
            .padding(.cfSpacing16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit Profile")
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                VStack(spacing: .cfSpacing12) {
                    Circle()
                        .fill(Color.cfFill)
                        .frame(width: 84, height: 84)
                    RoundedRectangle(cornerRadius: .cfRadius8)
                        .fill(Color.cfFill)
                        .frame(width: 140, height: 22)
                    RoundedRectangle(cornerRadius: .cfRadius8)
                        .fill(Color.cfFill)
                        .frame(width: 80, height: 16)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: .cfSpacing8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: .cfRadius12)
                            .fill(Color.cfFill)
                            .frame(height: 72)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing24)
        }
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Error state

    private func errorView(_ message: String) -> some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfSecondaryLabel)
            Text(message)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private static func formatPoints(_ points: Int) -> String {
        if points >= 1_000 {
            let k = Double(points) / 1_000
            return String(format: "%.1fk", k)
        }
        return "\(points)"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ProfileView — loaded", traits: .sizeThatFitsLayout) {
    ProfileView(repository: FakeSocialRepository.loaded)
}

#Preview("ProfileView — loaded dark", traits: .sizeThatFitsLayout) {
    ProfileView(repository: FakeSocialRepository.loaded)
        .preferredColorScheme(.dark)
}

#Preview("ProfileView — error") {
    ProfileView(repository: FakeSocialRepository.errored)
}

#Preview("ProfileView — XXL text") {
    ProfileView(repository: FakeSocialRepository.loaded)
        .dynamicTypeSize(.accessibility3)
}
#endif
