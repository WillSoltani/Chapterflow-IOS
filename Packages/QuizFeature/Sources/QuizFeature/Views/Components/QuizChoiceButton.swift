import SwiftUI
import Models
import DesignSystem

/// A single answer-choice button in a quiz question.
///
/// Visual states:
/// - **Idle**: unselected, tappable.
/// - **Selected**: highlighted with the brand accent.
/// - **Correct** (post-submission): green checkmark, correct answer revealed.
/// - **Incorrect** (post-submission): red X for the user's wrong pick; green
///   for the correct choice.
///
/// No correctness logic lives here — all state is injected from ``QuizModel``.
public struct QuizChoiceButton: View {

    public enum DisplayState {
        case idle
        case selected
        case correct           // this choice is the server-confirmed correct answer
        case incorrectSelected // user picked this but it was wrong
    }

    public let choice: QuizChoice
    public let state: DisplayState
    public let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(choice: QuizChoice, state: DisplayState, onTap: @escaping () -> Void) {
        self.choice = choice
        self.state = state
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: .cfSpacing12) {
                indicator
                    .frame(width: 24, height: 24)

                Text(choice.text)
                    .font(.cfBody)
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.cfSpacing16)
            .background(backgroundShape)
            .contentShape(RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .buttonStyle(.plain)
        .disabled(state == .correct || state == .incorrectSelected)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
        .animation(reduceMotion ? nil : .spring(response: 0.25), value: state)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .idle:
            Circle()
                .strokeBorder(Color.cfSeparator, lineWidth: 1.5)
                .background(Circle().fill(Color.cfSecondaryBackground))
        case .selected:
            Circle()
                .fill(Color.cfAccent)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )
        case .correct:
            Circle()
                .fill(Color.green.opacity(0.15))
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                )
        case .incorrectSelected:
            Circle()
                .fill(Color.red.opacity(0.15))
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                )
        }
    }

    @ViewBuilder
    private var backgroundShape: some View {
        switch state {
        case .idle:
            RoundedRectangle(cornerRadius: .cfRadius12)
                .fill(Color.cfSecondaryBackground)
        case .selected:
            RoundedRectangle(cornerRadius: .cfRadius12)
                .fill(Color.cfAccent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .strokeBorder(Color.cfAccent, lineWidth: 1.5)
                )
        case .correct:
            RoundedRectangle(cornerRadius: .cfRadius12)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .strokeBorder(Color.green.opacity(0.6), lineWidth: 1.5)
                )
        case .incorrectSelected:
            RoundedRectangle(cornerRadius: .cfRadius12)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5)
                )
        }
    }

    private var labelColor: Color {
        switch state {
        case .idle:      return Color.cfLabel
        case .selected:  return .cfAccent
        case .correct:   return .green
        case .incorrectSelected: return .red
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:             return choice.text
        case .selected:         return "\(choice.text), selected"
        case .correct:          return "\(choice.text), correct answer"
        case .incorrectSelected: return "\(choice.text), your answer, incorrect"
        }
    }
}
