import SwiftUI
import Models
import CoreKit
import DesignSystem

/// The top-level Quiz view.
///
/// Lifecycle:
/// 1. Fetch quiz from server (`.loading` phase → skeleton).
/// 2. User answers questions (`.active` phase).
///    - Every selection is saved as an account-scoped local draft.
///    - Offline actions save only; reconnect never submits automatically.
/// 3. After submission: `.result` phase shows ``QuizResultView``.
///
/// Entry point for a book chapter quiz:
/// ```swift
/// QuizView(bookId: "b-abc", chapterNumber: 1, repository: liveRepo, onContinue: { ... })
/// ```
public struct QuizView: View {

    static let savedDraftOfflineMessage = String(
        localized: "Draft saved on this device. Connect and tap Submit Quiz for grading."
    )

    @State private var model: QuizModel
    @State private var selectionFeedbackTrigger = 0
    public let onContinue: () -> Void
    /// Fired once when the server-graded *pass* result first appears. Used by the host to
    /// mark a genuine positive moment (e.g. to consider an App Store review request). Never
    /// fires on a failure, local draft, or error result.
    public let onQuizPassed: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        bookId: String,
        chapterNumber: Int,
        tone: ToneKey? = nil,
        repository: any QuizRepository,
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        analytics: any AnalyticsClient = NoopAnalyticsClient(),
        onContinue: @escaping () -> Void,
        onQuizPassed: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: QuizModel(
            bookId: bookId,
            chapterNumber: chapterNumber,
            tone: tone,
            repository: repository,
            workPermit: workPermit,
            analytics: analytics
        ))
        self.onContinue = onContinue
        self.onQuizPassed = onQuizPassed
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
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
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
                onRetry: { Task { await model.retry() } },
                onQuizPassed: onQuizPassed
            )
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
                if let message = model.submissionMessage {
                    submitNotice(message)
                }
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
                                selectionFeedbackTrigger += 1
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
            if model.requiresSessionRefresh {
                refreshRequiredBanner
            } else if !model.isOnline {
                offlineBanner
            } else if !model.allAnswered {
                unansweredHint
            }

            Button {
                Task {
                    if model.requiresSessionRefresh {
                        await model.load()
                    } else {
                        await model.submit()
                    }
                }
            } label: {
                Group {
                    if model.requiresSessionRefresh {
                        Label("Refresh Quiz", systemImage: "arrow.clockwise")
                    } else if !model.isOnline {
                        Label("Save Draft", systemImage: "square.and.arrow.down")
                    } else {
                        Text("Submit Quiz")
                    }
                }
                .font(.cfHeadline)
                .frame(maxWidth: .infinity)
                .padding(.cfSpacing16)
                .background(
                    primaryActionEnabled
                        ? Color.cfAccent
                        : Color.cfSecondaryBackground,
                    in: RoundedRectangle(cornerRadius: .cfRadius12)
                )
                .foregroundStyle(primaryActionEnabled ? .white : Color.cfTertiaryLabel)
            }
            .buttonStyle(.plain)
            .disabled(!primaryActionEnabled)
            .accessibilityLabel(submitAccessibilityLabel)
            .padding(.horizontal, .cfSpacing20)
            .padding(.vertical, .cfSpacing16)
        }
        .background(reduceTransparency ? AnyShapeStyle(Color.cfBackground) : AnyShapeStyle(.regularMaterial))
    }

    private var offlineBanner: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "wifi.slash")
                .font(.cfCaption)
                .accessibilityHidden(true)
            offlineMessage
                .font(.cfCaption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, .cfSpacing20)
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var offlineMessage: some View {
        switch model.draftState {
        case .saved, .savedRequiresConnection:
            Text(Self.savedDraftOfflineMessage)
        case .saving:
            Text("Saving this draft. Grading requires a connection.")
        case .failed:
            Text("Draft not saved. Keep this screen open and try again.")
        case .none:
            Text("Offline. Save this draft on this device; grading requires a connection.")
        }
    }

    private var refreshRequiredBanner: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.cfCaption)
                .accessibilityHidden(true)
            Text(refreshRequiredMessage)
                .font(.cfCaption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, .cfSpacing20)
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
    }

    private var refreshRequiredMessage: String {
        switch model.session?.status {
        case .passed:
            return String(localized: "This quiz is complete on the server.")
        case .cooldown:
            return String(localized: "The server says this quiz is cooling down. Refresh before retrying.")
        case .ready, .unknown, nil:
            return String(localized: "Refresh this quiz to get a valid server attempt before submitting.")
        }
    }

    private func submitNotice(_ message: String) -> some View {
        Label(message, systemImage: "info.circle")
            .font(.cfCallout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.cfSpacing12)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
            .accessibilityElement(children: .combine)
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
        if model.requiresSessionRefresh { return "Refresh quiz from the server" }
        if !model.isOnline { return "Save quiz draft on this device. Grading requires a connection" }
        if !model.allAnswered {
            let answered = model.selectedAnswers.count
            let total = model.session?.questions.count ?? 0
            return "Submit — \(answered) of \(total) answered"
        }
        return "Submit Quiz"
    }

    private var primaryActionEnabled: Bool {
        model.requiresSessionRefresh || model.canSubmit
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
