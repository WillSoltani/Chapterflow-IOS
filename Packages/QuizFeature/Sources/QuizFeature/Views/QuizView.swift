import SwiftUI
import Models
import CoreKit
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

/// The top-level Quiz view.
///
/// Lifecycle:
/// 1. Fetch quiz from server (`.loading` phase → skeleton).
/// 2. User answers questions (`.active` phase).
///    - Submit disabled offline: shows "Connect to submit" banner.
///    - Submit disabled until all questions answered.
/// 3. After submission: `.result` phase shows ``QuizResultView``.
///
/// Entry point for a book chapter quiz:
/// ```swift
/// QuizView(bookId: "b-abc", chapterNumber: 1, repository: liveRepo, onContinue: { ... })
/// ```
public struct QuizView: View {

    @State private var model: QuizModel
    public let onContinue: () -> Void

    public init(
        bookId: String,
        chapterNumber: Int,
        tone: ToneKey? = nil,
        repository: any QuizRepository,
        analytics: any AnalyticsClient = NoopAnalyticsClient(),
        onContinue: @escaping () -> Void
    ) {
        _model = State(initialValue: QuizModel(
            bookId: bookId,
            chapterNumber: chapterNumber,
            tone: tone,
            repository: repository,
            analytics: analytics
        ))
        self.onContinue = onContinue
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Chapter \(model.chapterNumber) Quiz")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .task {
            model.startConnectivityMonitor()
            await model.load()
        }
        .onDisappear {
            model.stopConnectivityMonitor()
        }
    }

    // MARK: - Phase routing

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            loadingView
        case .active:
            activeView
        case .submitting:
            submittingView
        case .result:
            QuizResultView(
                model: model,
                onContinue: onContinue,
                onRetry: { Task { await model.retry() } }
            )
        case .pendingGrading:
            pendingGradingView
        case .error(let msg):
            errorView(msg)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: .cfSpacing20) {
            ForEach(0..<3, id: \.self) { _ in
                CFSkeleton()
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: .cfRadius16))
            }
        }
        .padding(.cfSpacing20)
    }

    // MARK: - Active quiz

    private var activeView: some View {
        ScrollView {
            VStack(spacing: .cfSpacing16) {
                if let session = model.session {
                    ForEach(Array(session.questions.enumerated()), id: \.element.id) { index, question in
                        QuizQuestionCard(
                            index: index,
                            total: session.questions.count,
                            question: question,
                            selectedChoiceId: model.selectedAnswers[question.questionId],
                            questionResult: nil,
                            onSelect: { choiceId in
                                model.selectAnswer(choiceId, for: question.questionId)
                                triggerSelectionHaptic()
                            }
                        )
                    }
                }

                Spacer(minLength: .cfSpacing8)
            }
            .padding(.cfSpacing20)
            .padding(.bottom, 120)  // room for the sticky submit area
        }
        .overlay(alignment: .bottom) {
            submitArea
        }
    }

    // MARK: - Submit area

    private var submitArea: some View {
        VStack(spacing: 0) {
            if !model.isOnline {
                offlineBanner
            } else if !model.allAnswered {
                unansweredHint
            }

            Button {
                Task { await model.submit() }
            } label: {
                Group {
                    if !model.isOnline {
                        Label("Save for Later", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    } else {
                        Text("Submit Quiz")
                    }
                }
                .font(.cfHeadline)
                .frame(maxWidth: .infinity)
                .padding(.cfSpacing16)
                .background(
                    model.canSubmit
                        ? Color.cfAccent
                        : Color.cfSecondaryBackground,
                    in: RoundedRectangle(cornerRadius: .cfRadius12)
                )
                .foregroundStyle(model.canSubmit ? .white : Color.cfTertiaryLabel)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSubmit)
            .accessibilityLabel(submitAccessibilityLabel)
            .padding(.horizontal, .cfSpacing20)
            .padding(.vertical, .cfSpacing16)
        }
        .background(.regularMaterial)
    }

    private var offlineBanner: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "wifi.slash")
                .font(.cfCaption)
            Text("Offline — answers will be graded when you reconnect.")
                .font(.cfCaption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, .cfSpacing20)
        .padding(.vertical, .cfSpacing8)
        .accessibilityLabel("You are offline. Your answers will be saved and graded when you reconnect.")
    }

    // MARK: - Pending grading

    private var pendingGradingView: some View {
        ContentUnavailableView {
            Label("Awaiting Grading", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .symbolRenderingMode(.hierarchical)
        } description: {
            Text("Your answers have been saved. We'll grade them automatically when you're back online.")
                .font(.cfCallout)
                .foregroundStyle(.secondary)
        } actions: {
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(.cfAccent)
        }
        .accessibilityLabel("Your quiz answers are saved and waiting to be graded.")
    }

    private var unansweredHint: some View {
        let session = model.session
        let answered = model.selectedAnswers.count
        let total = session?.questions.count ?? 0
        return Text("\(answered) of \(total) answered")
            .font(.cfCaption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, .cfSpacing20)
            .padding(.top, .cfSpacing8)
            .accessibilityLabel("\(answered) of \(total) questions answered")
    }

    private var submitAccessibilityLabel: String {
        if !model.isOnline { return "Save answers for grading when back online" }
        if !model.allAnswered {
            let answered = model.selectedAnswers.count
            let total = model.session?.questions.count ?? 0
            return "Submit — \(answered) of \(total) answered"
        }
        return "Submit Quiz"
    }

    // MARK: - Submitting spinner

    private var submittingView: some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Grading…")
                .font(.cfSubheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Submitting your answers for grading")
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load Quiz", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await model.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.cfAccent)
        }
    }

    // MARK: - Haptics

    private func triggerSelectionHaptic() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Quiz — loading") {
    QuizView(
        bookId: "b-atomic-habits",
        chapterNumber: 1,
        repository: QuizPreviewData.passRepo,
        onContinue: {}
    )
}

#Preview("Quiz — active (partial answers)") {
    let model = QuizPreviewData.activeModel()
    return QuizView(
        bookId: "b-atomic-habits",
        chapterNumber: 1,
        repository: QuizPreviewData.passRepo,
        onContinue: {}
    )
    .task { _ = model }  // suppress unused warning
}

#Preview("Quiz — passed result") {
    let model = QuizPreviewData.passedModel()
    return QuizResultView(
        model: model,
        onContinue: {},
        onRetry: {}
    )
}

#Preview("Quiz — passed result (dark)") {
    let model = QuizPreviewData.passedModel()
    return QuizResultView(
        model: model,
        onContinue: {},
        onRetry: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Quiz — failed with cooldown") {
    let model = QuizPreviewData.failedModel()
    return QuizResultView(
        model: model,
        onContinue: {},
        onRetry: {}
    )
}

#Preview("Quiz — offline (submit disabled)") {
    let model = QuizPreviewData.activeModel()
    model.injectActiveForPreview(
        session: QuizPreviewData.session,
        selectedAnswers: ["q-1": "c-1-b", "q-2": "c-2-a", "q-3": "c-3-b"],
        isOnline: false
    )
    return QuizResultView(
        model: model,
        onContinue: {},
        onRetry: {}
    )
}

#Preview("Quiz — XXL text") {
    QuizView(
        bookId: "b-atomic-habits",
        chapterNumber: 1,
        repository: QuizPreviewData.passRepo,
        onContinue: {}
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
