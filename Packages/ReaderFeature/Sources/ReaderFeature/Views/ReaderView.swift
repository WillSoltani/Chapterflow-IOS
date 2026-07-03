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
/// quiz, audio, and AI flows.
public struct ReaderView: View {
    @State private var readerModel: ReaderModel
    @State private var didFireEndHaptic = false

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
        let appearance = ReadingAppearance(preferences: controlsModel.preferences)

        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ReadingProgressBar(
                    readPercent: readerModel.readPercent,
                    timeLeftMinutes: controlsModel.timeLeftMinutes
                )

                ReaderControlSurface(
                model: controlsModel,
                annotationModel: readerModel.annotationModel
            )
            }

            if readerModel.showQuizCTA {
                ChapterEndCTA(
                    chapterTitle: controlsModel.resolvedChapter.title,
                    onTakeQuiz: readerModel.onTakeQuiz,
                    onListen: readerModel.onListen,
                    onAsk: readerModel.onAsk
                )
            }
        }
        .background(appearance.colors.pageBg)
        .animation(.spring(duration: 0.35), value: readerModel.showQuizCTA)
        .onChange(of: controlsModel.currentTopBlockIndex) { _, newIndex in
            readerModel.didScrollToBlock(
                newIndex,
                blockCount: controlsModel.blocks.count,
                chapterId: controlsModel.resolvedChapter.chapterId
            )
        }
        .onChange(of: readerModel.isAtChapterEnd) { _, atEnd in
            // Haptic tick when the user first reaches the end of the chapter.
            if atEnd, !didFireEndHaptic {
                didFireEndHaptic = true
                hapticTick()
            }
        }
        .readerNavigationHidden(controlsModel.isFocusModeActive)
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
