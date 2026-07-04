import SwiftUI
import DesignSystem

/// The "Invite Friends" referral programme screen.
///
/// Shows the user's unique referral code, a share link, how rewards work,
/// invite stats (pending / activated / pro), and earned rewards — all
/// server-provided. Never computes or grants rewards client-side.
///
/// A "Got a friend's code?" button leads to ``EnterReferralCodeView``, the
/// manual attribution fallback required because iOS has no deferred deep-link
/// API (a code in a referral link cannot survive a fresh App Store install).
public struct ReferralView: View {

    @State private var model: ReferralModel
    @State private var enterCodePresented = false
    @State private var shareLinkText: String = ""

    /// Pre-filled when opened via a `chapterflow://ref/{code}` deep link.
    /// Non-empty causes the "Enter Code" sheet to open immediately.
    @State private var pendingDeepLinkCode: String

    private let repository: any SocialRepository

    public init(repository: any SocialRepository, pendingReferralCode: String = "") {
        self.repository = repository
        _model = State(initialValue: ReferralModel(repository: repository))
        _pendingDeepLinkCode = State(initialValue: pendingReferralCode)
    }

    public var body: some View {
        content
            .navigationTitle("Invite Friends")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .refreshable { await model.load() }
            .sheet(isPresented: $enterCodePresented) {
                EnterReferralCodeView(
                    model: model,
                    initialCode: pendingDeepLinkCode
                )
                .onDisappear { pendingDeepLinkCode = "" }
            }
            .task { await model.load() }
            .onAppear {
                if !pendingDeepLinkCode.isEmpty {
                    enterCodePresented = true
                }
            }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle where model.referralProfile == nil,
             .loading where model.referralProfile == nil:
            loadingSkeleton
        case .error(let message):
            errorView(message)
        default:
            if let profile = model.referralProfile {
                loadedScrollView(profile: profile)
            }
        }
    }

    // MARK: - Loaded

    private func loadedScrollView(profile: ReferralProfile) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                heroSection(profile: profile)
                howItWorksSection
                statsSection(stats: profile.stats)
                if !profile.rewards.isEmpty {
                    rewardsSection(rewards: profile.rewards)
                }
                enterCodeRow
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing24)
        }
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Hero / share section

    private func heroSection(profile: ReferralProfile) -> some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.cfAccent)

            Text("Invite friends, earn rewards")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)

            Text("Share your code and your friends get the ChapterFlow experience. You both earn rewards when they sign up and upgrade.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)

            codeCard(profile: profile)
        }
        .frame(maxWidth: .infinity)
    }

    private func codeCard(profile: ReferralProfile) -> some View {
        VStack(spacing: .cfSpacing12) {
            Text(profile.code)
                .font(.system(.title, design: .monospaced, weight: .semibold))
                .foregroundStyle(Color.cfLabel)
                .tracking(4)
                .accessibilityLabel("Referral code: \(profile.code)")

            ShareLink(
                item: profile.resolvedShareURL,
                subject: Text("Join me on ChapterFlow"),
                message: Text("Use my invite code \(profile.code) to sign up: \(profile.resolvedShareURL.absoluteString)")
            ) {
                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                    .font(.cfHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.cfSpacing12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Share invite link for code \(profile.code)")
        }
        .padding(.cfSpacing20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
    }

    // MARK: - How it works

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("How it works")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            VStack(spacing: .cfSpacing8) {
                howItWorksStep(
                    number: "1",
                    title: "Share your code",
                    detail: "Send your unique link or code to a friend."
                )
                howItWorksStep(
                    number: "2",
                    title: "Friend signs up",
                    detail: "They create an account using your invite."
                )
                howItWorksStep(
                    number: "3",
                    title: "Earn rewards",
                    detail: "You both get rewards — more when they go Pro."
                )
            }
            .padding(.cfSpacing16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
        }
    }

    private func howItWorksStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            Text(number)
                .font(.cfHeadline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.cfAccent, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(title)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                Text(detail)
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(detail)")
    }

    // MARK: - Stats

    private func statsSection(stats: ReferralStats) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Your invites")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            HStack(spacing: .cfSpacing8) {
                statPill(value: stats.pending, label: "Pending", color: .yellow)
                statPill(value: stats.activated, label: "Signed up", color: .blue)
                statPill(value: stats.pro, label: "Pro", color: Color.cfAccent)
            }
        }
    }

    private func statPill(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: .cfSpacing4) {
            Text("\(value)")
                .font(.cfTitle2)
                .foregroundStyle(color)
            Text(label)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .cfSpacing12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - Rewards

    private func rewardsSection(rewards: [ReferralReward]) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Rewards")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            VStack(spacing: .cfSpacing8) {
                ForEach(Array(rewards.enumerated()), id: \.offset) { _, reward in
                    rewardRow(reward: reward)
                }
            }
            .padding(.cfSpacing16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
        }
    }

    private func rewardRow(reward: ReferralReward) -> some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: reward.kind.systemImageName)
                .font(.cfBody)
                .foregroundStyle(reward.isEarned ? Color.cfAccent : Color.cfTertiaryLabel)
                .frame(width: .cfIconSmall)

            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text(reward.title)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                Text(reward.description)
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }

            Spacer()

            if reward.isEarned {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Earned")
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .accessibilityLabel("Not yet earned")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(reward.title): \(reward.description). \(reward.isEarned ? "Earned" : "Not yet earned")"
        )
    }

    // MARK: - Enter code row

    private var enterCodeRow: some View {
        VStack(spacing: .cfSpacing8) {
            Divider()

            Button {
                pendingDeepLinkCode = ""
                enterCodePresented = true
            } label: {
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundStyle(Color.cfAccent)
                        .frame(width: .cfIconSmall)
                    Text("Got a friend's code?")
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
            .accessibilityLabel("Enter a friend's referral code")
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                VStack(spacing: .cfSpacing12) {
                    Circle()
                        .fill(Color.cfFill)
                        .frame(width: 64, height: 64)
                    RoundedRectangle(cornerRadius: .cfRadius8)
                        .fill(Color.cfFill)
                        .frame(width: 200, height: 24)
                    RoundedRectangle(cornerRadius: .cfRadius8)
                        .fill(Color.cfFill)
                        .frame(width: 280, height: 16)
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .fill(Color.cfFill)
                        .frame(height: 96)
                }
                RoundedRectangle(cornerRadius: .cfRadius16)
                    .fill(Color.cfFill)
                    .frame(height: 160)
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

    // MARK: - Error

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
}

// MARK: - Previews

#if DEBUG
#Preview("ReferralView — loaded") {
    NavigationStack {
        ReferralView(repository: FakeSocialRepository.loaded)
    }
}

#Preview("ReferralView — dark") {
    NavigationStack {
        ReferralView(repository: FakeSocialRepository.loaded)
    }
    .preferredColorScheme(.dark)
}

#Preview("ReferralView — XXL text") {
    NavigationStack {
        ReferralView(repository: FakeSocialRepository.loaded)
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("ReferralView — error") {
    NavigationStack {
        ReferralView(repository: FakeSocialRepository.errored)
    }
}

#Preview("ReferralView — deep link pre-filled") {
    NavigationStack {
        ReferralView(repository: FakeSocialRepository.loaded, pendingReferralCode: "FRIEND99")
    }
}
#endif
