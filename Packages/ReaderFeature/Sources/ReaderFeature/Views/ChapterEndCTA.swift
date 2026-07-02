import SwiftUI
import DesignSystem

/// A floating bottom panel that appears once the user has substantially read
/// the chapter (~85 % +). Contains the primary "Take the quiz" action plus
/// optional "Listen" and "Ask about this" entry points.
///
/// The panel uses a material background so it feels native to the reading
/// surface without fully obscuring the content beneath.
public struct ChapterEndCTA: View {
    public let chapterTitle: String
    public let onTakeQuiz: (() -> Void)?
    public let onListen: (() -> Void)?
    public let onAsk: (() -> Void)?

    public init(
        chapterTitle: String,
        onTakeQuiz: (() -> Void)? = nil,
        onListen: (() -> Void)? = nil,
        onAsk: (() -> Void)? = nil
    ) {
        self.chapterTitle = chapterTitle
        self.onTakeQuiz = onTakeQuiz
        self.onListen = onListen
        self.onAsk = onAsk
    }

    public var body: some View {
        VStack(spacing: .cfSpacing12) {
            completionHint

            if onTakeQuiz != nil {
                quizButton
            }

            if onListen != nil || onAsk != nil {
                secondaryActions
            }
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing16)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: .cfRadius20)
        )
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: -4)
        .padding(.horizontal, .cfSpacing16)
        .padding(.bottom, .cfSpacing8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Completion hint

    private var completionHint: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.cfAccent)
                .font(.cfCallout)
            Text("Chapter complete — nice work!")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfLabel)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Quiz button

    private var quizButton: some View {
        Button {
            onTakeQuiz?()
        } label: {
            Label("Take the quiz", systemImage: "checkmark.seal")
                .font(.cfHeadline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(Color.cfAccent, in: RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take the quiz for this chapter")
        .accessibilityHint("Tests your understanding of \(chapterTitle)")
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: .cfSpacing8) {
            if let onListen {
                secondaryButton(
                    label: "Listen",
                    icon: "headphones",
                    action: onListen,
                    accessibilityLabel: "Listen to audio narration"
                )
            }
            if let onAsk {
                secondaryButton(
                    label: "Ask about this",
                    icon: "bubble.left.and.bubble.right",
                    action: onAsk,
                    accessibilityLabel: "Ask the AI about this chapter"
                )
            }
        }
    }

    private func secondaryButton(
        label: String,
        icon: String,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.cfSubheadline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Color.cfAccent)
                .background(Color.cfAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: .cfRadius8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Chapter end CTA — all actions") {
    ZStack(alignment: .bottom) {
        Color.cfBackground.ignoresSafeArea()
        ChapterEndCTA(
            chapterTitle: "The Surprising Power of Atomic Habits",
            onTakeQuiz: {},
            onListen: {},
            onAsk: {}
        )
    }
}

#Preview("Chapter end CTA — quiz only") {
    ZStack(alignment: .bottom) {
        Color.cfBackground.ignoresSafeArea()
        ChapterEndCTA(
            chapterTitle: "Deep Work: The New Superpower",
            onTakeQuiz: {}
        )
    }
}

#Preview("Chapter end CTA — dark") {
    ZStack(alignment: .bottom) {
        Color.cfBackground.ignoresSafeArea()
        ChapterEndCTA(
            chapterTitle: "The Surprising Power of Atomic Habits",
            onTakeQuiz: {},
            onListen: {},
            onAsk: {}
        )
    }
    .preferredColorScheme(.dark)
}
#endif
