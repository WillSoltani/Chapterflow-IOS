import SwiftUI
import DesignSystem

struct PaywallSuccessOverlay: View {
    let isActive: Bool
    let reduceMotion: Bool
    let onContinue: () -> Void

    @AccessibilityFocusState private var successMessageIsFocused: Bool

    var body: some View {
        ZStack {
            Color.cfGroupedBackground
                .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: .cfSpacing24) {
                        Spacer(minLength: .cfSpacing24)
                        successMessage

                        Button("Continue", action: onContinue)
                            .font(.cfHeadline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: .cfSpacing48)
                            .buttonStyle(.borderedProminent)
                            .tint(Color.cfAccent)
                        Spacer(minLength: .cfSpacing24)
                    }
                    .padding(.horizontal, .cfSpacing24)
                    .padding(.vertical, .cfSpacing32)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            if !reduceMotion {
                CFConfetti(isActive: isActive)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var successMessage: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: .cfIconLarge))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            Text("You're Pro!")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Your subscription is active. Enjoy unlimited access.")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Purchase successful. You're now a Pro member.")
        .accessibilityFocused($successMessageIsFocused)
        .task {
            successMessageIsFocused = true
        }
    }
}

#Preview("Success overlay — reduced motion") {
    PaywallSuccessOverlay(isActive: true, reduceMotion: true, onContinue: {})
        .dynamicTypeSize(.accessibility5)
}
