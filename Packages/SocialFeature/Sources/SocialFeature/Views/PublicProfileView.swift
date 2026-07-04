import SwiftUI
import Models
import DesignSystem

/// Read-only profile view for a reading partner (another user).
///
/// Receives a `userId` and loads the public profile on appear.
/// This view is reused by P7.2 (Reading Partners) for the partner detail screen.
///
/// Safety features (P7.7): block/unblock and report are available via the toolbar
/// menu. Blocked users see a blocked-state banner instead of profile content.
public struct PublicProfileView: View {

    @State private var model: PublicProfileModel

    public init(userId: String, repository: any SocialRepository) {
        _model = State(initialValue: PublicProfileModel(userId: userId, repository: repository))
    }

    public var body: some View {
        content
            .navigationTitle(model.profile?.displayName ?? "Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SafetyMenuButton(
                        displayName: model.profile?.displayName,
                        isBlocked: model.isBlocked,
                        isLoading: model.isSubmittingBlock,
                        onBlockTapped: { model.showBlockConfirmation = true },
                        onUnblockTapped: { Task { await model.unblockUser() } },
                        onReportTapped: { model.showReportSheet = true }
                    )
                }
            }
            .sheet(isPresented: $model.showBlockConfirmation) {
                BlockConfirmationView(
                    displayName: model.profile?.displayName,
                    isLoading: model.isSubmittingBlock,
                    onBlock: { Task { await model.blockUser() } },
                    onCancel: { model.showBlockConfirmation = false }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $model.showReportSheet) {
                ReportView(
                    displayName: model.profile?.displayName,
                    onSubmit: { reason, details in
                        await model.submitReport(reason: reason, details: details)
                    },
                    onCancel: { model.showReportSheet = false }
                )
            }
            .alert("Error", isPresented: Binding(
                get: { model.safetyError != nil },
                set: { if !$0 { /* model clears on next action */ } }
            )) {
                Button("OK") {}
            } message: {
                Text(model.safetyError ?? "")
            }
            .refreshable { await model.load() }
            .task { await model.load() }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if model.isBlocked {
            blockedBanner
        } else {
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
    }

    // MARK: - Blocked state

    private var blockedBanner: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "hand.raised.fill")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfSecondaryLabel)
            Text("You've blocked this user")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
            Text("They can't pair with you, send nudges, or view your profile. You can unblock them using the menu above.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Loaded state

    private func loadedScrollView(profile: PublicProfile) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                publicProfileHeader(profile: profile)
                statsGrid(profile: profile)

                if profile.equippedFrame != nil || profile.equippedTheme != nil {
                    cosmeticsSection(profile: profile)
                }

                badgesChip(count: profile.badgeCount)
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing24)
        }
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Header

    private func publicProfileHeader(profile: PublicProfile) -> some View {
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

    private func statsGrid(profile: PublicProfile) -> some View {
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
                icon: "🏅",
                value: "\(profile.badgeCount)",
                label: "Badges"
            )
        }
    }

    // MARK: - Cosmetics section

    private func cosmeticsSection(profile: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Equipped")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: .cfSpacing8) {
                if let frame = profile.equippedFrame {
                    cosmeticRow(label: "Frame", name: frame.name, systemImage: "circle.dashed")
                }
                if let theme = profile.equippedTheme {
                    cosmeticRow(label: "Theme", name: theme.name, systemImage: "paintpalette")
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

    // MARK: - Badges chip

    private func badgesChip(count: Int) -> some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "medal.fill")
                .foregroundStyle(Color.cfAccent)
            Text("\(count) Badge\(count == 1 ? "" : "s") Earned")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
            Spacer()
        }
        .padding(.cfSpacing16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
        .accessibilityLabel("\(count) badges earned")
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
            Image(systemName: "person.slash")
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
}

// MARK: - Previews

#if DEBUG
#Preview("PublicProfileView — loaded") {
    NavigationStack {
        PublicProfileView(
            userId: "user-partner",
            repository: FakeSocialRepository.loaded
        )
    }
}

#Preview("PublicProfileView — dark") {
    NavigationStack {
        PublicProfileView(
            userId: "user-partner",
            repository: FakeSocialRepository.loaded
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("PublicProfileView — blocked user") {
    NavigationStack {
        PublicProfileView(
            userId: "user-partner",
            repository: FakeSocialRepository.withBlocked(userId: "user-partner")
        )
    }
}

#Preview("PublicProfileView — error") {
    NavigationStack {
        PublicProfileView(
            userId: "user-partner",
            repository: FakeSocialRepository.errored
        )
    }
}

#Preview("PublicProfileView — XXL text") {
    NavigationStack {
        PublicProfileView(
            userId: "user-partner",
            repository: FakeSocialRepository.loaded
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
