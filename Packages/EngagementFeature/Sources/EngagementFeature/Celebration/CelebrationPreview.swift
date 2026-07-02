import SwiftUI
import DesignSystem
import Models

// MARK: - CelebrationView previews

#Preview("Celebration — full sequence (light)") {
    CelebrationSequencePreviewHost()
}

#Preview("Celebration — full sequence (dark)") {
    CelebrationSequencePreviewHost()
        .preferredColorScheme(.dark)
}

#Preview("Celebration — XXL Dynamic Type") {
    CelebrationSequencePreviewHost()
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

// Reduce Motion preview: enable in Simulator → Settings → Accessibility → Motion → Reduce Motion.
#Preview("Celebration — insightSpark (no confetti)") {
    @Previewable @State var presenter = CelebrationPresenter()
    ZStack {
        Color.cfGroupedBackground.ignoresSafeArea()
        Button("Show Insight Spark") {
            presenter.enqueue(.insightSpark(prompt: "How does habit stacking apply to your morning routine?"))
            presenter.present()
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.cfAccent)
    }
    .celebrationOverlay(presenter)
}

// MARK: - Host view

/// A self-contained host that starts a multi-event sequence on tap.
@MainActor
private struct CelebrationSequencePreviewHost: View {
    @State private var presenter = CelebrationPresenter()

    var body: some View {
        ZStack {
            Color.cfGroupedBackground.ignoresSafeArea()
            VStack(spacing: .cfSpacing24) {
                Text("ChapterFlow")
                    .font(.cfLargeTitle)
                    .foregroundStyle(Color.cfAccent)
                Text("Tap the button to simulate\na multi-reward sequence.")
                    .font(.cfBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Complete Chapter 3") {
                    enqueueSampleSequence()
                    presenter.present()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cfAccent)
            }
            .padding(.cfSpacing32)
        }
        .celebrationOverlay(presenter)
    }

    private func enqueueSampleSequence() {
        presenter.enqueue([
            .loopComplete(chapterTitle: "The Compound Effect"),
            .flowPointsGained(points: 75),
            .streakIncrement(newStreak: 7),
            .streakMilestone(streak: 7),
            .tierUp(newTier: "Analyst", previousTier: "Reader"),
            .badgeEarned(badge: BadgeItem(
                badgeId: "first-week",
                name: "7-Day Streak",
                description: "You read every day for a week.",
                category: "habit",
                isEarned: true,
                earnedAt: nil,
                icon: nil
            )),
            .insightSpark(prompt: "How does habit stacking apply to your morning routine?"),
        ])
    }
}
