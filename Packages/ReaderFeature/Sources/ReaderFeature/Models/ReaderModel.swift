import Foundation
import Observation
import Models
import Persistence

// MARK: - Load phase

/// The asynchronous loading lifecycle for a chapter.
///
/// Not `Sendable` — only accessed from `@MainActor` contexts.
public enum ReaderPhase {
    case loading
    case loaded(ReaderControlsModel)
    case failed(String)
}

// MARK: - ReaderModel

/// The primary orchestrator for the reader screen.
///
/// Responsibilities (in addition to those already in `ReaderControlsModel`):
/// - Fetches the chapter from `ReaderRepository` and constructs the controls model.
/// - Saves and restores the exact reading position (block-index anchor) across
///   launches — survives font-size and theme changes by construction.
/// - PATCHes the server cursor forward-only (never claims unlock/completion;
///   gating stays server-truth).
/// - Posts reading-session heartbeats every ~30 s of active reading.
/// - Exposes `readPercent`, `isAtChapterEnd`, and `showQuizCTA` for the UI,
///   driven by the scroll-position feedback loop through `ReaderControlsModel`.
/// - Provides injected-closure entry points for "Listen" (P6.2) and
///   "Ask about this" (P6.1) so this package stays free of AI dependencies.
@Observable
@MainActor
public final class ReaderModel {

    // MARK: - Public state

    /// The loading lifecycle — drives what the host view renders.
    public private(set) var phase: ReaderPhase = .loading

    /// Fraction of the chapter read (0…1). Mirrors the controls model's value
    /// once loaded; stays at 0 while loading.
    public private(set) var readPercent: Double = 0

    /// Whether the user has reached the end of the chapter (≥ 95 %).
    /// The view observes this to trigger a haptic tick.
    public private(set) var isAtChapterEnd: Bool = false

    /// Whether the "Take the quiz" CTA should be visible (≥ 85 % read).
    public private(set) var showQuizCTA: Bool = false

    // MARK: - Injected entry points

    /// Called when the user taps "Take the quiz". Set by the host (e.g. AppFeature).
    public var onTakeQuiz: (() -> Void)?

    /// Called when the user taps "Listen". Wired to P6.2 audio by the host.
    public var onListen: (() -> Void)?

    /// Called when the user taps "Ask about this". Wired to P6.1 AI by the host.
    public var onAsk: (() -> Void)?

    // MARK: - Configuration

    public let bookId: String
    public let chapterNumber: Int
    public let variantFamily: VariantFamily

    // MARK: - Internal

    @ObservationIgnored private let repository: any ReaderRepository
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let store: KeyValueStore

    /// The chapter number of the last successful cursor PATCH sent to the server.
    /// Used to enforce forward-only semantics.
    @ObservationIgnored private var lastPatchedChapterNumber: Int = 0

    /// The server's reported cursor chapter number at load time.
    /// Initialised from `BookProgress.currentChapterNumber`.
    @ObservationIgnored private var serverCursorChapterNumber: Int = 0

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?

    /// readPercent threshold above which chapter-end state triggers.
    public static let chapterEndThreshold: Double = 0.95

    /// readPercent threshold above which the quiz CTA appears.
    public static let quizCTAThreshold: Double = 0.85

    // MARK: - Init

    public init(
        bookId: String,
        chapterNumber: Int,
        variantFamily: VariantFamily,
        repository: any ReaderRepository,
        preferences: AppPreferences,
        store: KeyValueStore = KeyValueStore()
    ) {
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.variantFamily = variantFamily
        self.repository = repository
        self.preferences = preferences
        self.store = store
    }

    // MARK: - Lifecycle

    /// Fetches the chapter and constructs the controls model.
    /// Always resets to `.loading` — safe for retry on error.
    public func load() {
        loadTask?.cancel()
        phase = .loading
        readPercent = 0
        isAtChapterEnd = false
        showQuizCTA = false
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
    }

    /// Stops heartbeats and fires a best-effort final cursor PATCH.
    /// Call from `.onDisappear` on the hosting view.
    public func onDisappear() {
        stopHeartbeats()
        loadTask?.cancel()
        if case .loaded(let controlsModel) = phase {
            let chapterId = controlsModel.resolvedChapter.chapterId
            patchCursorIfNeeded(chapterId: chapterId)
        }
    }

    // MARK: - Scroll feedback

    /// Called by the host view when `controlsModel.currentTopBlockIndex` changes.
    ///
    /// Updates progress flags, saves the position, and schedules a cursor PATCH
    /// once the user reaches the chapter end.
    public func didScrollToBlock(_ blockIndex: Int, blockCount: Int, chapterId: String) {
        guard blockCount > 0 else { return }

        let newPercent = min(1.0, Double(blockIndex + 1) / Double(blockCount))
        readPercent = newPercent
        isAtChapterEnd = newPercent >= Self.chapterEndThreshold
        showQuizCTA = newPercent >= Self.quizCTAThreshold

        repository.saveScrollPosition(
            bookId: bookId,
            chapterNumber: chapterNumber,
            blockIndex: blockIndex
        )

        if isAtChapterEnd {
            patchCursorIfNeeded(chapterId: chapterId)
        }
    }

    // MARK: - Heartbeats

    /// Starts the 30-second heartbeat loop.
    public func startHeartbeats() {
        stopHeartbeats()
        guard case .loaded(let controlsModel) = phase else { return }
        let chapterId = controlsModel.resolvedChapter.chapterId
        let bId = bookId
        let repo = repository
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await repo.postReadingHeartbeat(bookId: bId, chapterId: chapterId)
            }
        }
    }

    /// Stops the heartbeat loop.
    public func stopHeartbeats() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Private

    private func performLoad() async {
        do {
            let response = try await repository.getChapter(
                bookId: bookId,
                n: chapterNumber,
                mode: nil
            )
            guard !Task.isCancelled else { return }

            let chapter = response.chapter
            let progress = response.progress

            serverCursorChapterNumber = progress.currentChapterNumber
            lastPatchedChapterNumber = progress.currentChapterNumber

            let controlsModel = ReaderControlsModel(
                chapter: chapter,
                bookId: bookId,
                variantFamily: variantFamily,
                preferences: preferences,
                store: store
            )

            // Restore saved reading position.
            if let saved = repository.loadScrollPosition(bookId: bookId, chapterNumber: chapterNumber),
               saved > 0 {
                controlsModel.pendingScrollAnchor = min(saved, controlsModel.blocks.count - 1)
            }

            phase = .loaded(controlsModel)
            startHeartbeats()

        } catch is CancellationError {
            // Cancelled — phase remains loading; the next load() call will retry.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// PATCHes the server cursor when the current chapter number exceeds
    /// the last patched value. Forward-only; never sends a lower number.
    private func patchCursorIfNeeded(chapterId: String) {
        guard chapterNumber > lastPatchedChapterNumber else { return }
        lastPatchedChapterNumber = chapterNumber
        let bId = bookId
        let repo = repository
        Task {
            try? await repo.patchBookCursor(bookId: bId, chapterId: chapterId)
        }
    }
}
