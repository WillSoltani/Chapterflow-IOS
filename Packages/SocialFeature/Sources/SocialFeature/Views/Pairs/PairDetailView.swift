import SwiftUI
import DesignSystem
import CoreKit

/// Detail view for a reading partnership.
///
/// Shows the partner's avatar, name, tier, streak + books stats, and lets the
/// user send a nudge or end the partnership. Reuses the ``AvatarView`` component
/// from the existing profile surface.
public struct PairDetailView: View {

    @State private var currentPair: ReadingPair
    private let model: PairsModel

    @State private var showUnpairConfirm = false
    @State private var nudgeSuccessVisible = false
    @Environment(\.dismiss) private var dismiss

    public init(pair: ReadingPair, model: PairsModel) {
        _currentPair = State(initialValue: pair)
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                partnerHeader
                statsGrid
                if currentPair.status == .active {
                    actionButtons
                }
                if currentPair.status == .expired {
                    expiredBanner
                }
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing24)
        }
        .background(Color.cfGroupedBackground)
        .navigationTitle(currentPair.partnerDisplayName ?? "Partner")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(
            "End Partnership?",
            isPresented: $showUnpairConfirm,
            actions: {
                Button("End Partnership", role: .destructive) {
                    Task { await performUnpair() }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("You won't be able to see each other's progress any more. This can't be undone.")
            }
        )
        .overlay(alignment: .top) {
            if nudgeSuccessVisible {
                nudgeToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, .cfSpacing8)
            }
        }
        .onChange(of: model.lastNudgedPartnerId) { _, newValue in
            guard newValue == currentPair.partnerId else { return }
            withAnimation(.spring) { nudgeSuccessVisible = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.spring) { nudgeSuccessVisible = false }
            }
        }
        .alert("Error", isPresented: operationErrorBinding) {
            Button("OK", role: .cancel) { model.operationError = nil }
        } message: {
            Text(model.operationError ?? "")
        }
    }

    // MARK: - Header

    private var partnerHeader: some View {
        VStack(spacing: .cfSpacing12) {
            AvatarView(
                avatarUrl: currentPair.partnerAvatarUrl,
                avatarEmoji: currentPair.partnerAvatarEmoji,
                initials: currentPair.initials,
                equippedFrame: nil,
                size: 84
            )

            VStack(spacing: .cfSpacing4) {
                Text(currentPair.partnerDisplayName ?? "Reading Partner")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)

                tierBadge(currentPair.partnerTier)
            }

            if let pairedAt = currentPair.pairedAt {
                Text("Partners since \(formattedDate(pairedAt))")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
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

    // MARK: - Stats

    private var statsGrid: some View {
        HStack(spacing: .cfSpacing8) {
            ProfileStatItemView(
                icon: "🔥",
                value: "\(currentPair.partnerCurrentStreak)",
                label: "Streak"
            )
            ProfileStatItemView(
                icon: "📚",
                value: "\(currentPair.partnerBooksFinished)",
                label: "Books"
            )
            ProfileStatItemView(
                icon: "🤝",
                value: currentPair.status.displayLabel,
                label: "Status"
            )
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: .cfSpacing12) {
            nudgeButton
            unpairButton
        }
    }

    private var nudgeButton: some View {
        Button {
            Task { await model.nudge(partnerId: currentPair.partnerId) }
        } label: {
            HStack {
                if model.nudgingPartnerId == currentPair.partnerId {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "bell.fill")
                }
                Text("Send a Nudge")
                    .font(.cfBody)
            }
            .frame(maxWidth: .infinity)
            .padding(.cfSpacing12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.cfAccent)
        .disabled(model.nudgingPartnerId != nil)
        .accessibilityLabel("Send a nudge notification to \(currentPair.partnerDisplayName ?? "your partner")")
    }

    private var unpairButton: some View {
        Button(role: .destructive) {
            showUnpairConfirm = true
        } label: {
            HStack {
                if model.unpairingPartnerId == currentPair.partnerId {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "person.2.slash")
                }
                Text("End Partnership")
                    .font(.cfBody)
            }
            .frame(maxWidth: .infinity)
            .padding(.cfSpacing12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .disabled(model.unpairingPartnerId != nil)
        .accessibilityLabel("End reading partnership")
    }

    // MARK: - Expired banner

    private var expiredBanner: some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: "clock.badge.xmark")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text("Invite Expired")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfLabel)
                Text("This invite is no longer valid. Ask your partner to send a new one.")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    // MARK: - Nudge toast

    private var nudgeToast: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(Color.cfAccent)
            Text("Nudge sent!")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfLabel)
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel("Nudge sent successfully")
    }

    // MARK: - Helpers

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        // Fallback: trim the timestamp to a readable prefix.
        return String(iso.prefix(10))
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { model.operationError != nil },
            set: { if !$0 { model.operationError = nil } }
        )
    }

    private func performUnpair() async {
        await model.unpair(partnerId: currentPair.partnerId)
        if model.operationError == nil {
            dismiss()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("PairDetailView — active") {
    NavigationStack {
        PairDetailView(
            pair: ReadingPair.previewActive,
            model: PairsModel(repository: FakeSocialRepository.withPairs)
        )
    }
}

#Preview("PairDetailView — expired") {
    NavigationStack {
        PairDetailView(
            pair: ReadingPair.previewExpired,
            model: PairsModel(repository: FakeSocialRepository.withPairs)
        )
    }
}

#Preview("PairDetailView — dark") {
    NavigationStack {
        PairDetailView(
            pair: ReadingPair.previewActive,
            model: PairsModel(repository: FakeSocialRepository.withPairs)
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("PairDetailView — XXL text") {
    NavigationStack {
        PairDetailView(
            pair: ReadingPair.previewActive,
            model: PairsModel(repository: FakeSocialRepository.withPairs)
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
