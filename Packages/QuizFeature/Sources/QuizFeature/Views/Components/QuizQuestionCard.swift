import SwiftUI
import Models
import DesignSystem

/// Renders a single quiz question with its answer choices.
///
/// Pass `questionResult` after the user submits to reveal correct/incorrect state.
/// When `questionResult` is nil the card is in "active" mode: choices are tappable
/// and the selected one is simply highlighted.
public struct QuizQuestionCard: View {

    public let index: Int
    public let total: Int
    public let question: QuizQuestion
    public let selectedChoiceId: String?
    public let questionResult: QuizQuestionResult?
    public let onSelect: (String) -> Void

    public init(
        index: Int,
        total: Int,
        question: QuizQuestion,
        selectedChoiceId: String?,
        questionResult: QuizQuestionResult?,
        onSelect: @escaping (String) -> Void
    ) {
        self.index = index
        self.total = total
        self.question = question
        self.selectedChoiceId = selectedChoiceId
        self.questionResult = questionResult
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            // Question number + prompt
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                Text("Question \(index + 1) of \(total)")
                    .font(.cfCaption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Question \(index + 1) of \(total)")

                Text(question.prompt)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Answer choices
            VStack(spacing: .cfSpacing8) {
                ForEach(question.choices) { choice in
                    QuizChoiceButton(
                        choice: choice,
                        state: displayState(for: choice),
                        onTap: {
                            guard questionResult == nil else { return }
                            onSelect(choice.choiceId)
                        }
                    )
                }
            }

            // Post-result note: show correct answer label if user was wrong
            if let result = questionResult, !result.isCorrect {
                correctAnswerLabel(correctChoiceId: result.correctChoiceId)
            }
        }
        .padding(.cfSpacing20)
        .background(
            RoundedRectangle(cornerRadius: .cfRadius16)
                .fill(.regularMaterial)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Helpers

    private func displayState(for choice: QuizChoice) -> QuizChoiceButton.DisplayState {
        guard let result = questionResult else {
            // Active mode: just show selection
            return choice.choiceId == selectedChoiceId ? .selected : .idle
        }
        // Review mode: server grading revealed
        if choice.choiceId == result.correctChoiceId {
            return .correct
        }
        if choice.choiceId == result.selectedChoiceId && !result.isCorrect {
            return .incorrectSelected
        }
        return .idle
    }

    @ViewBuilder
    private func correctAnswerLabel(correctChoiceId: String) -> some View {
        if let correctChoice = question.choices.first(where: { $0.choiceId == correctChoiceId }) {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.cfCaption)
                Text("Correct: \(correctChoice.text)")
                    .font(.cfCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, .cfSpacing4)
            .accessibilityLabel("Correct answer: \(correctChoice.text)")
        }
    }
}
