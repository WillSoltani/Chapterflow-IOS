import SwiftUI
import DesignSystem
import CoreKit

/// Lets a user preview and claim a gift code.
///
/// Two entry points:
/// 1. Deep link — `initialCode` is pre-filled; the preview loads automatically.
/// 2. Manual entry — user types/pastes the code, then taps "Preview Gift".
///
/// After a successful claim the caller is responsible for re-fetching entitlements;
/// this view never grants Pro client-side.
public struct GiftClaimView: View {

    @State private var model: GiftModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    private let onClaimed: (() -> Void)?

    /// - Parameters:
    ///   - code: Pre-fill the code field (e.g. from a deep link). When non-nil,
    ///     the preview is triggered automatically on appear.
    ///   - repository: The social data layer.
    ///   - onClaimed: Called after a successful claim so the parent can
    ///     trigger an entitlement refresh.
    public init(
        code: String? = nil,
        repository: any SocialRepository,
        onClaimed: (() -> Void)? = nil
    ) {
        _model = State(initialValue: GiftModel(repository: repository, initialCode: code))
        self.onClaimed = onClaimed
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Redeem Gift")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { closeButton }
        }
        .task {
            // Auto-preview when launched from a deep link with a code.
            if !model.codeInput.isEmpty {
                await model.previewGift(code: model.codeInput)
            }
        }
    }

    // MARK: - State routing

    @ViewBuilder
    private var content: some View {
        switch model.claimPhase {
        case .idle:
            entryView
        case .loadingPreview:
            loadingView("Loading gift…")
        case .preview(let gift):
            previewView(gift)
        case .claiming:
            loadingView("Claiming gift…")
        case .claimed(let result):
            claimedView(result)
        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - Entry (manual code input)

    private var entryView: some View {
        ScrollView {
            VStack(spacing: .cfSpacing32) {
                VStack(spacing: .cfSpacing12) {
                    ZStack {
                        Circle()
                            .fill(Color.cfAccent.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Text("🎁")
                            .font(.system(size: 40))
                    }
                    .accessibilityHidden(true)

                    Text("You Have a Gift!")
                        .font(.cfTitle2)
                        .foregroundStyle(Color.cfLabel)

                    Text("Enter the gift code you received to preview and claim your Pro access.")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.center)
                }

                codeEntryField

                Button {
                    Task { await model.previewGift(code: model.codeInput) }
                } label: {
                    Text("Preview Gift")
                        .font(.cfHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .cfSpacing12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cfAccent)
                .disabled(model.codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Preview the gift with the entered code")
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.vertical, .cfSpacing32)
        }
        .background(Color.cfGroupedBackground)
    }

    private var codeEntryField: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text("Gift Code")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            TextField("e.g. GIFT1234", text: $model.codeInput)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .submitLabel(.search)
                #endif
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .onSubmit {
                    Task { await model.previewGift(code: model.codeInput) }
                }
                .padding(.vertical, .cfSpacing12)
                .padding(.horizontal, .cfSpacing16)
                .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .strokeBorder(
                            fieldFocused ? Color.cfAccent : Color.cfSeparator,
                            lineWidth: fieldFocused ? 2 : 1
                        )
                )
                .accessibilityLabel("Gift code input field")
        }
    }

    // MARK: - Loading

    private func loadingView(_ label: String) -> some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
                .scaleEffect(1.4)
            Text(label)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfGroupedBackground)
        .accessibilityLabel(label)
    }

    // MARK: - Preview (confirm before claiming)

    private func previewView(_ gift: Gift) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing32) {
                VStack(spacing: .cfSpacing12) {
                    ZStack {
                        Circle()
                            .fill(Color.cfAccent.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Text("🎁")
                            .font(.system(size: 40))
                    }
                    .accessibilityHidden(true)

                    Text("You've Got a Gift!")
                        .font(.cfTitle2)
                        .foregroundStyle(Color.cfLabel)

                    if let sender = gift.senderDisplayName {
                        Text("From \(sender)")
                            .font(.cfBody)
                            .foregroundStyle(Color.cfSecondaryLabel)
                    }
                }

                giftPreviewCard(gift)

                // Expiry warning
                if let expiresAt = gift.expiresAt {
                    HStack(spacing: .cfSpacing8) {
                        Image(systemName: "clock")
                            .font(.cfCaption)
                        Text("Expires \(expiresAt)")
                            .font(.cfCaption)
                    }
                    .foregroundStyle(Color.cfSecondaryLabel)
                }

                VStack(spacing: .cfSpacing12) {
                    Button {
                        Task {
                            await model.claimGift(code: gift.code)
                        }
                    } label: {
                        Text("Claim Gift")
                            .font(.cfHeadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, .cfSpacing12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cfAccent)
                    .accessibilityLabel("Claim this gift and activate Pro access")

                    Button("Enter a different code") {
                        model.resetClaim()
                    }
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .accessibilityLabel("Cancel and enter a different gift code")
                }
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.vertical, .cfSpacing32)
        }
        .background(Color.cfGroupedBackground)
    }

    private func giftPreviewCard(_ gift: Gift) -> some View {
        VStack(spacing: .cfSpacing16) {
            HStack {
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(gift.giftTypeLabel)
                        .font(.cfHeadline)
                        .foregroundStyle(Color.cfLabel)
                    Text("Full Pro access")
                        .font(.cfFootnote)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                Spacer()
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(Color.cfAccent)
            }

            Divider()

            Text(gift.code)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.cfTertiaryLabel)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Gift code: \(gift.code)")
        }
        .padding(.cfSpacing16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
    }

    // MARK: - Claimed (success)

    private func claimedView(_ result: GiftClaimResult) -> some View {
        VStack(spacing: .cfSpacing32) {
            Spacer()

            VStack(spacing: .cfSpacing16) {
                ZStack {
                    Circle()
                        .fill(Color.cfAccent.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.cfAccent)
                }

                Text("You're Pro!")
                    .font(.cfLargeTitle)
                    .foregroundStyle(Color.cfLabel)

                if let message = result.message {
                    Text(message)
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Your \(result.gift.giftTypeLabel) has been activated. Enjoy full Pro access!")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.center)
                }

                Text("Entitlement updates on next launch or account refresh.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Done") {
                onClaimed?()
                dismiss()
            }
            .font(.cfHeadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing12)
            .buttonStyle(.borderedProminent)
            .tint(.cfAccent)
            .accessibilityLabel("Dismiss and return to the app")
            .padding(.horizontal, .cfSpacing24)
            .padding(.bottom, .cfSpacing32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .padding(.horizontal, .cfSpacing8)

            Button("Try Again") {
                model.resetClaim()
            }
            .buttonStyle(.borderedProminent)
            .tint(.cfAccent)
            .accessibilityLabel("Try entering the gift code again")
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Toolbar

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .accessibilityLabel("Close gift redemption sheet")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("GiftClaimView — entry") {
    GiftClaimView(repository: FakeSocialRepository.loaded)
}

#Preview("GiftClaimView — entry dark") {
    GiftClaimView(repository: FakeSocialRepository.loaded)
        .preferredColorScheme(.dark)
}

#Preview("GiftClaimView — entry XXL") {
    GiftClaimView(repository: FakeSocialRepository.loaded)
        .dynamicTypeSize(.accessibility3)
}

#Preview("GiftClaimView — deep link (code pre-filled)") {
    GiftClaimView(code: "GIFT0001", repository: FakeSocialRepository.withPendingGift)
}

#Preview("GiftClaimView — already claimed") {
    GiftClaimView(code: "CLMD0001", repository: FakeSocialRepository.withClaimedGift)
}
#endif
