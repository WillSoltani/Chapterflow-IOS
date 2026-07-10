#if DEBUG
import SwiftUI

/// A small developer/QA aid that visualises ``ReviewPromptPolicy`` decisions.
///
/// The in-app review prompt itself is a system-provided sheet with no custom UI, so this
/// inspector stands in as the previewable surface: adjust the streak and see, for the
/// current app version, which moments would (and would not) trigger a review — and why.
///
/// Built entirely from system components (`Form`, `LabeledContent`, `Stepper`, SF Symbols)
/// so it carries no hardcoded design values and adopts the platform look automatically.
/// Compiled only in `DEBUG`.
struct ReviewPromptPolicyInspector: View {

    /// The app version the policy evaluates against.
    let currentVersion: String
    /// A previously-prompted version, to demonstrate the once-per-version cap.
    let lastPromptedVersion: String?

    @State private var streakDays: Int

    init(
        currentVersion: String = "1.0",
        lastPromptedVersion: String? = nil,
        streakDays: Int = ReviewPromptPolicy.minimumStreakForQuizPrompt
    ) {
        self.currentVersion = currentVersion
        self.lastPromptedVersion = lastPromptedVersion
        _streakDays = State(initialValue: streakDays)
    }

    private var moments: [(label: String, moment: ReviewPromptMoment)] {
        [
            ("Passed quiz", .quizCompleted(passed: true, currentStreakDays: streakDays)),
            ("Failed quiz", .quizCompleted(passed: false, currentStreakDays: streakDays)),
            ("Finished book", .bookFinished),
        ]
    }

    var body: some View {
        Form {
            Section("Context") {
                LabeledContent("App version", value: currentVersion)
                LabeledContent("Last prompted", value: lastPromptedVersion ?? "Never")
                Stepper(value: $streakDays, in: 0...30) {
                    LabeledContent("Reading streak", value: "\(streakDays) day\(streakDays == 1 ? "" : "s")")
                }
                LabeledContent(
                    "Quiz streak threshold",
                    value: "\(ReviewPromptPolicy.minimumStreakForQuizPrompt) days"
                )
            }

            Section {
                ForEach(moments, id: \.label) { entry in
                    let fires = ReviewPromptPolicy.shouldRequestReview(
                        for: entry.moment,
                        currentVersion: currentVersion,
                        lastPromptedVersion: lastPromptedVersion
                    )
                    Label {
                        Text(entry.label)
                    } icon: {
                        Image(systemName: fires ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(fires ? .green : .secondary)
                    }
                    .accessibilityLabel("\(entry.label): \(fires ? "would prompt" : "would not prompt")")
                }
            } header: {
                Text("Would request a review?")
            } footer: {
                Text("The system still governs the final display, capping prompts to three per year.")
            }
        }
    }
}

#Preview("Inspector — light") {
    ReviewPromptPolicyInspector()
}

#Preview("Inspector — dark") {
    ReviewPromptPolicyInspector()
        .preferredColorScheme(.dark)
}

#Preview("Inspector — XXL") {
    ReviewPromptPolicyInspector(streakDays: 2)
        .dynamicTypeSize(.accessibility3)
}
#endif
