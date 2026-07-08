import SwiftUI
import DesignSystem
import CoreKit

/// Lets the user create a shareable "pro_week" gift code and share it.
///
/// Flow: idle → tap "Create Gift Code" → `.creating` → `.created(gift)`
/// → user copies the code or uses the system share sheet.
public struct GiftSendView: View {

    @State private var model: GiftModel
    @Environment(\.dismiss) private var dismiss

    public init(repository: any SocialRepository) {
        _model = State(initialValue: GiftModel(repository: repository))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Gift Pro")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { closeButton }
        }
    }

    // MARK: - State routing

    @ViewBuilder
    private var content: some View {
        switch model.sendPhase {
        case .idle:
            idleView
        case .creating:
            loadingView
        case .created(let gift):
            createdView(gift)
        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        ScrollView {
            VStack(spacing: .cfSpacing32) {
                giftIllustration

                VStack(spacing: .cfSpacing12) {
                    Text("Share the Gift of Learning")
                        .font(.cfTitle2)
                        .foregroundStyle(Color.cfLabel)
                        .multilineTextAlignment(.center)

                    Text("Generate a gift code and share it with a friend. They'll get one week of Pro access — offline reading, AI features, and more.")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.center)
                }

                giftCard

                Button {
                    Task { await model.createGift() }
                } label: {
                    Text("Create Gift Code")
                        .font(.cfHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .cfSpacing12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cfAccent)
                .accessibilityLabel("Create a gift code for 1 week of Pro access")
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.vertical, .cfSpacing32)
        }
        .background(Color.cfGroupedBackground)
    }

    private var giftIllustration: some View {
        ZStack {
            Circle()
                .fill(Color.cfAccent.opacity(0.12))
                .frame(width: 96, height: 96)
            Text("🎁")
                .font(.system(size: 44))
        }
        .accessibilityHidden(true)
    }

    private var giftCard: some View {
        VStack(spacing: .cfSpacing16) {
            HStack {
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("1 Week of Pro")
                        .font(.cfHeadline)
                        .foregroundStyle(Color.cfLabel)
                    Text("Full access · 7 days")
                        .font(.cfFootnote)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                Spacer()
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(Color.cfAccent)
            }

            Divider()

            VStack(alignment: .leading, spacing: .cfSpacing8) {
                benefitRow("book.closed.fill",    "Offline reading")
                benefitRow("sparkles",            "AI Ask the Book")
                benefitRow("waveform",            "Audio narration")
                benefitRow("star.fill",           "Unlimited books")
            }
        }
        .padding(.cfSpacing16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
    }

    private func benefitRow(_ icon: String, _ label: String) -> some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: icon)
                .font(.cfFootnote)
                .foregroundStyle(Color.cfAccent)
                .frame(width: 16)
            Text(label)
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Creating gift code…")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfGroupedBackground)
        .accessibilityLabel("Creating gift code, please wait")
    }

    // MARK: - Created

    private func createdView(_ gift: Gift) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing32) {
                VStack(spacing: .cfSpacing12) {
                    ZStack {
                        Circle()
                            .fill(Color.cfAccent.opacity(0.12))
                            .frame(width: 96, height: 96)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.cfAccent)
                    }

                    Text("Gift Code Created!")
                        .font(.cfTitle2)
                        .foregroundStyle(Color.cfLabel)

                    Text("Share this code with a friend. They can redeem it at app.chapterflow.ca or in the app.")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.center)
                }

                codeDisplayCard(gift)

                // ShareLink uses the chapterflow:// scheme as specified.
                // Recipients without the app see a human-readable fallback message.
                if let shareURL = URL(string: "chapterflow://gift/\(gift.code)") {
                    ShareLink(
                        item: shareURL,
                        subject: Text("A gift for you 🎁"),
                        message: Text("Here's your ChapterFlow gift code: \(gift.code)\n\nRedeem at app.chapterflow.ca or in the app.")
                    ) {
                        HStack(spacing: .cfSpacing8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Gift Link")
                                .font(.cfHeadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .cfSpacing12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cfAccent)
                    .accessibilityLabel("Share gift link for \(gift.giftTypeLabel)")
                }

                Button("Create Another Gift") {
                    model.resetSend()
                }
                .font(.cfBody)
                .foregroundStyle(Color.cfAccent)
                .accessibilityLabel("Create another gift code")
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.vertical, .cfSpacing32)
        }
        .background(Color.cfGroupedBackground)
    }

    private func codeDisplayCard(_ gift: Gift) -> some View {
        VStack(spacing: .cfSpacing12) {
            Text(gift.giftTypeLabel)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            // The code — large, monospaced, copyable.
            Text(gift.code)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.cfLabel)
                .tracking(4)
                .accessibilityLabel("Gift code: \(gift.code.map(String.init).joined(separator: " "))")

            Button {
                #if os(iOS)
                UIPasteboard.general.string = gift.code
                #endif
            } label: {
                HStack(spacing: .cfSpacing4) {
                    Image(systemName: "doc.on.doc")
                        .font(.cfCaption)
                    Text("Copy Code")
                        .font(.cfCaption)
                }
                .foregroundStyle(Color.cfAccent)
            }
            .accessibilityLabel("Copy gift code to clipboard")
        }
        .frame(maxWidth: .infinity)
        .padding(.cfSpacing24)
        .background(Color.cfAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: .cfRadius16))
        .overlay(
            RoundedRectangle(cornerRadius: .cfRadius16)
                .strokeBorder(Color.cfAccent.opacity(0.25), lineWidth: 1)
        )
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
                model.resetSend()
            }
            .buttonStyle(.borderedProminent)
            .tint(.cfAccent)
            .accessibilityLabel("Try creating a gift code again")
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Toolbar

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .accessibilityLabel("Close gift sheet")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("GiftSendView — idle") {
    GiftSendView(repository: FakeSocialRepository.loaded)
}

#Preview("GiftSendView — idle dark") {
    GiftSendView(repository: FakeSocialRepository.loaded)
        .preferredColorScheme(.dark)
}

#Preview("GiftSendView — idle XXL") {
    GiftSendView(repository: FakeSocialRepository.loaded)
        .dynamicTypeSize(.accessibility3)
}

#Preview("GiftSendView — created") {
    let repo = FakeSocialRepository.withPendingGift
    return GiftSendView(repository: repo)
}
#endif
