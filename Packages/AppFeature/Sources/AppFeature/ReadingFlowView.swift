import SwiftUI
import Models
import Persistence
import ReaderFeature
import QuizFeature

// MARK: - Reading context (Identifiable so .fullScreenCover(item:) works)

/// The parameters needed to open a reading session.
struct ReadingFlow: Identifiable {
    let id = UUID()
    let bookId: String
    let chapterNumber: Int
    let variantFamily: VariantFamily
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
