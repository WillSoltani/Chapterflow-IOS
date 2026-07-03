import SwiftUI
import DesignSystem
#if os(iOS)
import UIKit
#endif

/// A full-screen overlay shown when the reading loop completes
/// (chapter read + quiz passed).
///
/// Presents a calm, typographic "loop complete" moment with confetti.
/// The user can tap "Continue" to advance to the next chapter, or dismiss
/// via the overlay background to stay in the current reader.
///
/// Respects Reduce Motion — confetti is suppressed when enabled.
public struct LoopCompletionOverlay: View {
    public let chapterTitle: String
    public let onContinue: (() -> Void)?
    public let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(
        chapterTitle: String,
        onContinue: (() -> Void)?,
        onDismiss: @escaping () -> Void
    ) {
        self.chapterTitle = chapterTitle
        self.onContinue = onContinue
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Scrim — tap to dismiss.
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)

            // Confetti layer (behind card, non-interactive).
            if !reduceMotion {
                CFConfetti(isActive: appeared)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            // Completion card.
            completionCard
                .padding(.horizontal, .cfSpacing24)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
            triggerHaptic()
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Card

    private var completionCard: some View {
        VStack(spacing: .cfSpacing20) {
            // Icon
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.cfAccent)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)

            VStack(spacing: .cfSpacing8) {
                Text("Chapter Complete")
                    .font(.cfTitle2.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)

                Text("\u{201C}\(chapterTitle)\u{201D}")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if let onContinue {
                Button(action: onContinue) {
                    Label("Continue to Next Chapter", systemImage: "arrow.right")
                        .font(.cfHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.cfSpacing16)
                        .foregroundStyle(.white)
                        .background(Color.cfAccent, in: RoundedRectangle(cornerRadius: .cfRadius12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Continue to the next chapter")
            }

            Button("Stay Here") {
                onDismiss()
            }
            .font(.cfSubheadline)
            .foregroundStyle(Color.cfSecondaryLabel)
            .accessibilityLabel("Stay in current chapter")
        }
        .padding(.cfSpacing24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius20))
        .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 8)
    }

    // MARK: - Haptic

    private func triggerHaptic() {
#if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Loop completion — with continue, light") {
    ZStack {
        Color.cfBackground.ignoresSafeArea()
        LoopCompletionOverlay(
            chapterTitle: "The Surprising Power of Atomic Habits",
            onContinue: {},
            onDismiss: {}
        )
    }
}

#Preview("Loop completion — no continue, dark") {
    ZStack {
        Color.cfBackground.ignoresSafeArea()
        LoopCompletionOverlay(
            chapterTitle: "Deep Work and the Focused Mind",
            onContinue: nil,
            onDismiss: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Loop completion — XXL text") {
    ZStack {
        Color.cfBackground.ignoresSafeArea()
        LoopCompletionOverlay(
            chapterTitle: "The Surprising Power of Atomic Habits",
            onContinue: {},
            onDismiss: {}
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
