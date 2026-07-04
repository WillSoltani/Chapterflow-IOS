import SwiftUI
import DesignSystem

/// Explicit consent step required before any reading-pair invitation is accepted or sent.
///
/// Apple Guideline 1.2 mandates a clear consent flow whenever the app enables
/// user-to-user contact. This view explains what pairing does, surfaces the Code
/// of Conduct, and requires an affirmative "I Agree" tap — dismissal alone is not
/// treated as consent.
public struct PairingConsentView: View {

    let partnerDisplayName: String?
    let onConsent: () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        partnerDisplayName: String?,
        onConsent: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.partnerDisplayName = partnerDisplayName
        self.onConsent = onConsent
        self.onDecline = onDecline
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .cfSpacing24) {
                    iconHeader
                    titleText
                    bulletList
                    conductNote
                    Spacer(minLength: .cfSpacing16)
                    actionButtons
                }
                .padding(.horizontal, .cfSpacing24)
                .padding(.vertical, .cfSpacing32)
            }
            .background(Color.cfGroupedBackground)
            .navigationTitle("Reading Partner Request")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Sub-views

    private var iconHeader: some View {
        ZStack {
            Circle()
                .fill(Color.cfAccent.opacity(0.12))
                .frame(width: 80, height: 80)
            Image(systemName: "person.2.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.cfAccent)
        }
    }

    private var titleText: some View {
        VStack(spacing: .cfSpacing8) {
            Text("Pair with \(partnerDisplayName ?? "this reader")?")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)

            Text("Pairing lets you share your reading journey with another person.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    private var bulletList: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            bulletRow(icon: "chart.bar.fill", text: "See each other's reading progress and streaks")
            bulletRow(icon: "bell.badge.fill", text: "Send and receive reading nudges (up to 3 per day)")
            bulletRow(icon: "person.crop.circle.fill", text: "View each other's public profiles")
            bulletRow(icon: "xmark.circle.fill", text: "Either partner can leave at any time")
        }
        .padding(.cfSpacing16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            Image(systemName: icon)
                .font(.cfBody)
                .foregroundStyle(Color.cfAccent)
                .frame(width: 20)
            Text(text)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
        }
    }

    private var conductNote: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Label("Code of Conduct", systemImage: "shield.checkered")
                .font(.cfSubheadline.weight(.medium))
                .foregroundStyle(Color.cfLabel)
            Text(
                "By pairing you agree to treat your partner respectfully. " +
                "Harassment, inappropriate nudges, or misuse of social features " +
                "may result in a block, report, or account suspension. " +
                "Use the ••• menu on any profile to block or report a user."
            )
            .font(.cfCaption)
            .foregroundStyle(Color.cfSecondaryLabel)
        }
        .padding(.cfSpacing16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius16))
    }

    private var actionButtons: some View {
        VStack(spacing: .cfSpacing12) {
            Button {
                onConsent()
                dismiss()
            } label: {
                Text("I Agree — Pair Up")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .cfSpacing12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Agree and start pairing")

            Button("Decline", role: .cancel) {
                onDecline()
                dismiss()
            }
            .foregroundStyle(Color.cfSecondaryLabel)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("PairingConsentView — light") {
    PairingConsentView(
        partnerDisplayName: "Reading Partner",
        onConsent: {},
        onDecline: {}
    )
}

#Preview("PairingConsentView — dark") {
    PairingConsentView(
        partnerDisplayName: "Reading Partner",
        onConsent: {},
        onDecline: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("PairingConsentView — XXL text") {
    PairingConsentView(
        partnerDisplayName: "Reading Partner",
        onConsent: {},
        onDecline: {}
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
