import SwiftUI
import DesignSystem
import Models

// MARK: - ReviewSessionView

/// Full-screen review session: card front → flip → back → four grade buttons.
///
/// Respects Reduce Motion: the card-flip animation is replaced with a simple
/// opacity fade when the system accessibility setting is active.
public struct ReviewSessionView: View {

    private let model: ReviewsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    public init(model: ReviewsModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch model.sessionState {
                case .inactive:
                    ProgressView()
                case .front:
                    if let card = model.currentCard {
                        sessionContent(card: card, frontVisible: true)
                    }
                case .back:
                    if let card = model.currentCard {
                        sessionContent(card: card, frontVisible: false)
                    }
                case .done(let count):
                    doneView(reviewed: count)
                }
            }
            .navigationTitle("Review")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.endSession()
                        dismiss()
                    }
                    .accessibilityLabel("Close review session")
                }
            }
            .background(Color.cfGroupedBackground.ignoresSafeArea())
        }
    }

    // MARK: - Session content

    private func sessionContent(card: FsrsCard, frontVisible: Bool) -> some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, .cfSpacing16)
                .padding(.top, .cfSpacing8)

            Spacer()

            cardView(card: card, frontVisible: frontVisible)
                .padding(.horizontal, .cfSpacing16)

            Spacer()

            if frontVisible {
                revealButton
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.bottom, .cfSpacing32)
            } else {
                gradeButtons
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.bottom, .cfSpacing32)
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let (done, total) = model.sessionProgress
        return VStack(spacing: .cfSpacing8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: .cfRadius4)
                        .fill(Color.cfSecondaryFill)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: .cfRadius4)
                        .fill(Color.cfAccent)
                        .frame(
                            width: total > 0 ? proxy.size.width * CGFloat(done) / CGFloat(total) : 0,
                            height: 4
                        )
                        .animation(.easeInOut(duration: 0.3), value: done)
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(done) of \(total)")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Spacer()
                Text("\(total - done) remaining")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
    }

    // MARK: - Card face

    private func cardView(card: FsrsCard, frontVisible: Bool) -> some View {
        ZStack {
            cardFace(text: card.front, isFront: true)
                .opacity(frontVisible ? 1 : 0)
                .scaleEffect(frontVisible ? 1 : 0.96)

            cardFace(text: card.back, isFront: false)
                .opacity(frontVisible ? 0 : 1)
                .scaleEffect(frontVisible ? 0.96 : 1)
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.8),
            value: frontVisible
        )
    }

    private func cardFace(text: String, isFront: Bool) -> some View {
        CFCard {
            VStack(spacing: .cfSpacing16) {
                Text(isFront ? "Question" : "Answer")
                    .font(.cfCaption)
                    .foregroundStyle(isFront ? Color.cfAccent : Color.cfSecondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                Text(text)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    // MARK: - Reveal button

    private var revealButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                model.revealBack()
            }
        } label: {
            Text("Show Answer")
                .font(.cfHeadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, .cfSpacing16)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.cfAccent)
        .accessibilityLabel("Show the card's answer")
    }

    // MARK: - Grade buttons

    private var gradeButtons: some View {
        VStack(spacing: .cfSpacing12) {
            Text("How well did you recall this?")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)

            HStack(spacing: .cfSpacing8) {
                ForEach(FSRSGrade.allCases) { grade in
                    GradeButton(grade: grade) {
                        model.grade(grade)
                    }
                }
            }
        }
    }

    // MARK: - Done view

    private func doneView(reviewed: Int) -> some View {
        VStack(spacing: .cfSpacing24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            VStack(spacing: .cfSpacing8) {
                Text("All caught up!")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)

                if reviewed > 0 {
                    Text("Reviewed \(reviewed) \(reviewed == 1 ? "card" : "cards")")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }

            Spacer()

            Button {
                model.endSession()
                dismiss()
            } label: {
                Text("Done")
                    .font(.cfHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .cfSpacing16)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .padding(.horizontal, .cfSpacing16)
            .padding(.bottom, .cfSpacing32)
            .accessibilityLabel("Finish and close the review session")
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - GradeButton

private struct GradeButton: View {
    let grade: FSRSGrade
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            #if canImport(UIKit)
            if !reduceMotion {
                UIImpactFeedbackGenerator(style: hapticStyle).impactOccurred()
            }
            #endif
            action()
        } label: {
            VStack(spacing: .cfSpacing4) {
                Text(grade.localizedTitle)
                    .font(.cfSubheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(foregroundColor)

                Text(grade.intervalHint)
                    .font(.cfCaption2)
                    .foregroundStyle(foregroundColor.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing12)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .accessibilityLabel("\(grade.localizedTitle) — \(grade.intervalHint)")
    }

    private var backgroundColor: Color {
        switch grade {
        case .again: return Color.red.opacity(0.12)
        case .hard:  return Color.orange.opacity(0.12)
        case .good:  return Color.cfAccent.opacity(0.12)
        case .easy:  return Color.green.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch grade {
        case .again: return .red
        case .hard:  return .orange
        case .good:  return Color.cfAccent
        case .easy:  return .green
        }
    }

    #if canImport(UIKit)
    private var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch grade {
        case .again: return .heavy
        case .hard:  return .medium
        case .good:  return .light
        case .easy:  return .soft
        }
    }
    #endif
}

// MARK: - Previews

#if DEBUG
import Networking
import Persistence

@MainActor
private func previewModel(sessionState: ReviewsModel.SessionState = .inactive) -> ReviewsModel {
    let model = ReviewsModel(repository: ReviewsRepository(apiClient: MockAPIClient()))
    model.sessionState = sessionState
    return model
}

private let sampleCard = FsrsCard(
    cardId: "c1", bookId: "b1", chapterId: "ch1",
    front: "What is the habit loop?",
    back: "Cue → Routine → Reward. The neurological loop that underlies every habit, as described in The Power of Habit.",
    dueAt: nil, stability: 5.0, difficulty: 4.5, state: .due,
    lastReviewAt: nil, reps: 2, lapses: 0, elapsedDays: 5.0, scheduledDays: 5, retrievability: 0.9
)

#Preview("Front of card") {
    let model = previewModel(sessionState: .front)
    return ReviewSessionView(model: model)
}

#Preview("Back + grade buttons", traits: .sizeThatFitsLayout) {
    let model = previewModel(sessionState: .back)
    return ReviewSessionView(model: model)
}

#Preview("Session complete") {
    let model = previewModel(sessionState: .done(reviewed: 12))
    return ReviewSessionView(model: model)
}

#Preview("Dark mode — back") {
    let model = previewModel(sessionState: .back)
    return ReviewSessionView(model: model)
        .preferredColorScheme(.dark)
}
#endif
