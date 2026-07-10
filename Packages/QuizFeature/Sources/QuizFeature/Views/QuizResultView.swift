import SwiftUI
import Models
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

/// Displays the server-graded quiz result.
///
/// - **Pass**: score, confetti, optional "next chapter unlocked" banner, and a Continue button.
/// - **Fail**: score, per-question review, and a live countdown to when the retry is eligible.
///   The retry button is disabled until ``QuizModel/canRetry`` becomes true.
///   Cooldown is derived from the server-authoritative ``QuizAttemptResult/cooldownSeconds``,
///   not the device clock, to dodge time-skew issues.
public struct QuizResultView: View {

    @Bindable var model: QuizModel
    public let onContinue: () -> Void
    public let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: QuizModel, onContinue: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.model = model
        self.onContinue = onContinue
        self.onRetry = onRetry
    }

    private var result: QuizAttemptResult? { model.result }

    public var body: some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                if let result {
                    scoreSummary(result)

                    if result.passed {
                        passActions(result)
                    } else {
                        failActions(result)
                    }

                    questionReview(result)
                }
            }
            .padding(.cfSpacing20)
            .padding(.bottom, .cfSpacing48)
        }
        .overlay(alignment: .top) {
            // Confetti runs on top of everything, non-interactive; suppressed when Reduce Motion is on.
            if let result, result.passed, !reduceMotion {
                CFConfetti(isActive: true)
                    .frame(height: 400)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            if let result, result.passed {
                triggerSuccessHaptic()
            }
        }
    }

    // MARK: - Score summary

    private func scoreSummary(_ result: QuizAttemptResult) -> some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(result.passed ? Color.green : Color.red)
                .symbolEffect(.bounce, value: reduceMotion ? false : result.passed)
                .accessibilityHidden(true)

            Text(result.passed ? "Quiz Passed!" : "Not Quite")
                .font(.cfTitle1)
                .foregroundStyle(Color.cfLabel)

            Text("\(result.scorePercent)%")
                .font(.cfLargeTitle)
                .foregroundStyle(result.passed ? Color.green : Color.red)
                .accessibilityLabel("Score: \(result.scorePercent) percent")

            Text("\(result.correctCount) of \(result.totalQuestions) correct")
                .font(.cfSubheadline)
                .foregroundStyle(.secondary)

            if !result.passed {
                Text("You need \(model.passingScorePercent)% to pass.")
                    .font(.cfCallout)
                    .foregroundStyle(.secondary)
            }

            if result.passed && model.unlockedNextChapter {
                nextChapterUnlockedBanner
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(scoreSummaryA11yLabel(result))
    }

    private func scoreSummaryA11yLabel(_ result: QuizAttemptResult) -> String {
        var parts = [result.passed ? "Quiz passed" : "Quiz not passed"]
        parts.append("Score: \(result.scorePercent) percent")
        parts.append("\(result.correctCount) of \(result.totalQuestions) correct")
        if !result.passed {
            parts.append("You need \(model.passingScorePercent)% to pass")
        }
        if result.passed && model.unlockedNextChapter {
            parts.append("Next chapter unlocked")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Pass actions

    private func passActions(_ result: QuizAttemptResult) -> some View {
        Button(action: onContinue) {
            Label("Continue", systemImage: "arrow.right")
                .font(.cfHeadline)
                .frame(maxWidth: .infinity)
                .padding(.cfSpacing16)
                .background(Color.cfAccent, in: RoundedRectangle(cornerRadius: .cfRadius12))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue to the next chapter")
    }

    // MARK: - Fail actions

    @ViewBuilder
    private func failActions(_ result: QuizAttemptResult) -> some View {
        VStack(spacing: .cfSpacing12) {
            if model.cooldownRemaining > 0 {
                CooldownBanner(remaining: model.cooldownRemaining)
            }

            Button(action: { Task { await model.retry() } }) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.cfHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.cfSpacing16)
                    .background(
                        model.canRetry
                            ? Color.cfAccent
                            : Color.cfSecondaryBackground,
                        in: RoundedRectangle(cornerRadius: .cfRadius12)
                    )
                    .foregroundStyle(model.canRetry ? .white : Color.cfTertiaryLabel)
            }
            .buttonStyle(.plain)
            .disabled(!model.canRetry)
            .accessibilityLabel(retryAccessibilityLabel)
        }
    }

    private var retryAccessibilityLabel: String {
        if model.canRetry { return "Try again" }
        let mins = Int(model.cooldownRemaining / 60)
        let secs = Int(model.cooldownRemaining) % 60
        return "Retry available in \(mins) minutes \(secs) seconds"
    }

    // MARK: - Question review

    private func questionReview(_ result: QuizAttemptResult) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Answer Review")
                .font(.cfTitle3)
                .padding(.bottom, .cfSpacing4)

            if let session = model.session {
                ForEach(Array(session.questions.enumerated()), id: \.element.id) { index, question in
                    let qResult = result.questionResults.first { $0.questionId == question.questionId }
                    QuizQuestionCard(
                        index: index,
                        total: session.questions.count,
                        question: question,
                        selectedChoiceId: qResult?.selectedChoiceId,
                        questionResult: qResult,
                        onSelect: { _ in }  // read-only in review mode
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Next chapter banner

    private var nextChapterUnlockedBanner: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "lock.open.fill")
                .foregroundStyle(Color.cfAccent)
            Text("Next chapter unlocked!")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfAccent)
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
        .background(
            RoundedRectangle(cornerRadius: .cfRadius8)
                .fill(Color.cfAccent.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius8)
                        .strokeBorder(Color.cfAccent.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityLabel("Next chapter is now unlocked")
    }

    // MARK: - Haptic

    private func triggerSuccessHaptic() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - Cooldown banner

/// Live countdown to the moment a failed quiz attempt can be retried.
///
/// Refreshes every second via a `TimelineView`. The countdown is driven by
/// ``QuizModel/cooldownRemaining`` which is anchored to
/// ``QuizAttemptResult/cooldownSeconds`` (server time), not the device clock.
private struct CooldownBanner: View {
    let remaining: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.secondary)
                Text("Retry in \(formattedCountdown)")
                    .font(.cfSubheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.cfSpacing12)
            .background(
                RoundedRectangle(cornerRadius: .cfRadius12)
                    .fill(Color.cfSecondaryBackground)
            )
        }
        .accessibilityLabel("Retry available in \(formattedCountdown)")
    }

    private var formattedCountdown: String {
        let total = max(0, Int(remaining))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
