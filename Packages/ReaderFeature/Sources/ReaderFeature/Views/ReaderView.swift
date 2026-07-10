import SwiftUI
import Models
import DesignSystem
import Persistence
#if os(iOS)
import UIKit
#endif

/// The full reader screen: chapter loading, content, progress tracking,
/// position restore, heartbeats, chapter-end CTA, and injected AI/audio hooks.
///
/// Create a `ReaderModel` and pass it to this view. Wire `readerModel.onTakeQuiz`,
/// `readerModel.onListen`, and `readerModel.onAsk` from the host to connect the
/// quiz, audio, and AI flows. Wire `readerModel.onLoopComplete` and
/// `readerModel.onContinueToNextChapter` to handle loop completion.
public struct ReaderView: View {
    @State private var readerModel: ReaderModel
    @State private var didFireEndHaptic = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(readerModel: ReaderModel) {
        _readerModel = State(initialValue: readerModel)
    }

    public var body: some View {
        ZStack {
            switch readerModel.phase {
            case .loading:
                loadingView

            case .loaded(let controlsModel):
                loadedView(controlsModel: controlsModel)

            case .failed(let message):
                errorView(message: message)
            }
        }
        .task { readerModel.load() }
        .onDisappear { readerModel.onDisappear() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading chapter…")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfBackground)
        .accessibilityLabel("Loading chapter")
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: .cfSpacing20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.cfAccent)
            Text("Couldn't load chapter")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
            Text(message)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try again") {
                readerModel.load()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .accessibilityLabel("Retry loading the chapter")
        }
        .padding(.cfSpacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfBackground)
    }

    // MARK: - Loaded

    private func loadedView(controlsModel: ReaderControlsModel) -> some View {
        let chapterTitle = controlsModel.resolvedChapter.title
        let navModel = readerModel.navModel
        let showPersistentSidebar = horizontalSizeClass == .regular
            && navModel?.isToCPresented == true

        return HStack(spacing: 0) {
            if showPersistentSidebar, let nav = navModel {
                TableOfContentsView(
                    model: nav,
                    currentReadPercent: readerModel.readPercent,
                    isSheet: false
                )
                .frame(width: 300)
                .background(Color.cfSecondaryBackground)
                Divider()
            }
            readerContentStack(controlsModel: controlsModel, chapterTitle: chapterTitle, navModel: navModel)
        }
        .animation(reduceMotion ? .none : .spring(duration: 0.35), value: readerModel.showQuizCTA)
        .animation(reduceMotion ? .none : .spring(duration: 0.35), value: readerModel.isLoopComplete)
        .animation(reduceMotion ? .none : .spring(duration: 0.3), value: showPersistentSidebar)
        .overlay {
            if readerModel.isLoopComplete {
                LoopCompletionOverlay(
                    chapterTitle: chapterTitle,
                    onContinue: readerModel.onContinueToNextChapter,
                    onDismiss: { readerModel.dismissLoopComplete() }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onChange(of: controlsModel.currentTopBlockIndex) { _, newIndex in
            readerModel.didScrollToBlock(
                newIndex,
                blockCount: controlsModel.blocks.count,
                chapterId: controlsModel.resolvedChapter.chapterId
            )
        }
        .onChange(of: readerModel.isAtChapterEnd) { _, atEnd in
            if atEnd, !didFireEndHaptic {
                didFireEndHaptic = true
                hapticTick()
            }
        }
        .onChange(of: controlsModel.isBookPreferencesPanelPresented) { _, isPresented in
            if isPresented {
                controlsModel.isBookPreferencesPanelPresented = false
                readerModel.onShowBookPreferences?()
            }
        }
        .readerNavigationHidden(controlsModel.isFocusModeActive)
    }

    @ViewBuilder
    private func readerContentStack(
        controlsModel: ReaderControlsModel,
        chapterTitle: String,
        navModel: ChapterNavModel?
    ) -> some View {
        let appearance = ReadingAppearance(preferences: controlsModel.preferences)
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ReadingProgressBar(
                    readPercent: readerModel.readPercent,
                    timeLeftMinutes: controlsModel.timeLeftMinutes
                )
                // Two-axis completion badges — shown when at least one axis is active.
                if readerModel.isKnowledgeComplete || readerModel.applicationState != .none {
                    HStack {
                        ChapterCompletionBadgesView(
                            isKnowledgeComplete: readerModel.isKnowledgeComplete,
                            applicationState: readerModel.applicationState
                        )
                        Spacer()
                    }
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.vertical, .cfSpacing8)
                    .background(appearance.colors.pageBg)
                }
                ReaderControlSurface(
                    model: controlsModel,
                    annotationModel: readerModel.annotationModel,
                    navModel: navModel
                )
            }
            if readerModel.showQuizCTA && !readerModel.isLoopComplete {
                ChapterEndCTA(
                    chapterTitle: chapterTitle,
                    onTakeQuiz: readerModel.onTakeQuiz,
                    onListen: readerModel.onListen,
                    onAsk: readerModel.onAsk,
                    onReflect: readerModel.onReflect
                )
            }
        }
        .background(appearance.colors.pageBg)
    }

    // MARK: - Helpers

    private func hapticTick() {
#if os(iOS)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
#endif
    }
}

// MARK: - Platform helpers

private extension View {
    /// Hides the navigation bar and status bar on iOS; no-op on other platforms.
    @ViewBuilder
    func readerNavigationHidden(_ hidden: Bool) -> some View {
#if os(iOS)
        self.navigationBarHidden(hidden)
            .statusBar(hidden: hidden)
#else
        self
#endif
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Reader — light (loading → loaded)") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.reader.light"))
    ReaderView(readerModel: ReaderModel(
        bookId: "atomic-habits",
        chapterNumber: 1,
        variantFamily: .emh,
        repository: FakeReaderRepository(),
        preferences: prefs
    ))
}

#Preview("Reader — dark") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.reader.dark"))
    ReaderView(readerModel: ReaderModel(
        bookId: "atomic-habits",
        chapterNumber: 1,
        variantFamily: .emh,
        repository: FakeReaderRepository(),
        preferences: prefs
    ))
    .preferredColorScheme(.dark)
}

#Preview("Reader — XXL text") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.reader.xxl"))
    ReaderView(readerModel: ReaderModel(
        bookId: "atomic-habits",
        chapterNumber: 1,
        variantFamily: .emh,
        repository: FakeReaderRepository(),
        preferences: prefs
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Reader — loop complete") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.reader.loop"))
    let repo = FakeReaderRepository()
    let model = ReaderModel(
        bookId: "atomic-habits",
        chapterNumber: 1,
        variantFamily: .emh,
        repository: repo,
        preferences: prefs
    )
    model.onContinueToNextChapter = {}
    // Trigger the overlay in a task after view appears.
    return ReaderView(readerModel: model)
        .task {
            try? await Task.sleep(for: .seconds(1))
            model.notifyLoopComplete()
        }
}

#Preview("Reader — error state") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.reader.err"))
    ReaderView(readerModel: ReaderModel(
        bookId: "atomic-habits",
        chapterNumber: 1,
        variantFamily: .emh,
        repository: FakeReaderRepository(
            chapterResponse: .failure(URLError(.notConnectedToInternet))
        ),
        preferences: prefs
    ))
}
#endif
