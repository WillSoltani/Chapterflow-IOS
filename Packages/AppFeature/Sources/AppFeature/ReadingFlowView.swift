import SwiftUI
import Models
import Persistence
import ReaderFeature
import QuizFeature
import CoreKit

// MARK: - Reading context (Identifiable so .fullScreenCover(item:) works)

/// The parameters needed to open a reading session.
struct ReadingFlow: Identifiable, Equatable {
    let id = UUID()
    let bookId: String
    let chapterNumber: Int
    let variantFamily: VariantFamily

    static func == (lhs: ReadingFlow, rhs: ReadingFlow) -> Bool {
        lhs.bookId == rhs.bookId
            && lhs.chapterNumber == rhs.chapterNumber
            && lhs.variantFamily == rhs.variantFamily
    }
}

// MARK: - Quiz context

/// The parameters needed to show the quiz for a chapter.
struct QuizContext: Identifiable {
    let id = UUID()
    let bookId: String
    let chapterNumber: Int
    let toneKey: ToneKey?
}

// MARK: - ReadingFlowView

/// Hosts the full reading session: a NavigationStack with ReaderView and
/// a sheet-based QuizView wired to the reader's chapter-end CTA.
///
/// Presented as a `.fullScreenCover` from `AppRootView` so that it sits on
/// top of the tab shell without disturbing the library navigation stack.
struct ReadingFlowView: View {
    @State private var readerModel: ReaderModel
    @State private var quizContext: QuizContext?

    private let quizRepository: any QuizRepository
    private let onDismiss: () -> Void

    @MainActor
    init(
        flow: ReadingFlow,
        readerRepository: any ReaderRepository,
        quizRepository: any QuizRepository,
        annotationRepository: (any AnnotationRepository)?,
        preferences: AppPreferences,
        onDismiss: @escaping () -> Void
    ) {
        _readerModel = State(initialValue: ReaderModel(
            bookId: flow.bookId,
            chapterNumber: flow.chapterNumber,
            variantFamily: flow.variantFamily,
            repository: readerRepository,
            preferences: preferences,
            annotationRepository: annotationRepository
        ))
        self.quizRepository = quizRepository
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ReaderView(readerModel: readerModel)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            onDismiss()
                        }
                        .accessibilityLabel("Close reader")
                    }
                    #else
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            onDismiss()
                        }
                        .accessibilityLabel("Close reader")
                    }
                    #endif
                }
        }
        .sheet(item: $quizContext) { ctx in
            QuizView(
                bookId: ctx.bookId,
                chapterNumber: ctx.chapterNumber,
                tone: ctx.toneKey,
                repository: quizRepository,
                onContinue: {
                    quizContext = nil
                    onDismiss()
                }
            )
        }
        .task {
            wireQuizCTA()
        }
        // Advertise the reading session for Continuity Handoff.
        // Sets webpageURL so non-iOS devices (e.g. Mac without the app) can open
        // the web equivalent in Safari.
        .userActivity(HandoffActivityType.reading) { activity in
            let bookId = readerModel.bookId
            let chapter = readerModel.chapterNumber
            let variantRaw = readerModel.variantFamily.rawValue
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = false
            activity.title = "Reading Chapter \(chapter)"
            activity.userInfo = [
                HandoffKeys.bookId: bookId,
                HandoffKeys.chapterNumber: chapter,
                HandoffKeys.variantFamily: variantRaw,
            ]
            activity.webpageURL = URL(
                string: "https://\(DeepLink.universalLinkDomain)/book/\(bookId)/chapter/\(chapter)"
            )
        }
    }

    // MARK: - Wiring

    @MainActor
    private func wireQuizCTA() {
        let rm = readerModel
        readerModel.onTakeQuiz = {
            guard case .loaded(let controls) = rm.phase else { return }
            quizContext = QuizContext(
                bookId: rm.bookId,
                chapterNumber: rm.chapterNumber,
                toneKey: controls.selectedTone
            )
        }
    }
}
