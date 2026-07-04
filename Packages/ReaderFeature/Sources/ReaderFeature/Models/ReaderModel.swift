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
/// - Manages the full reading-session lifecycle (start on load, heartbeat every
///   ~30 s of active reading, end on background/close). Heartbeats are paused
///   when no scroll activity has occurred for more than `inactivityThreshold`.
/// - Exposes `readPercent`, `isAtChapterEnd`, and `showQuizCTA` for the UI,
///   driven by the scroll-position feedback loop through `ReaderControlsModel`.
/// - Tracks two-axis chapter completion: `isKnowledgeComplete` (quiz passed,
///   server truth from `BookProgress`) and `applicationState` (committed/applied,
///   from `BookStateResponse.applicationStates`).
/// - Exposes `onLoopComplete` and `onContinueToNextChapter` for the host to
///   wire the celebration layer and chapter-advance navigation.
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

    // MARK: - Two-axis completion (server-authoritative; never set client-side)

    /// True when the server has marked this chapter's quiz as passed.
    /// Derived from `BookProgress.completedChapters` returned with the chapter.
    public private(set) var isKnowledgeComplete: Bool = false

    /// The user's application axis for this chapter (none / committed / applied).
    /// Loaded async from `GET /book/me/books/{bookId}/state`. `.none` until resolved.
    public private(set) var applicationState: ChapterApplicationState = .none

    // MARK: - Loop completion

    /// True once `notifyLoopComplete()` has been called (chapter read + quiz passed).
    /// The `ReaderView` uses this to show the completion overlay.
    public private(set) var isLoopComplete: Bool = false

    /// Called when the reading loop completes (chapter read + quiz passed).
    /// The host should wire this to show celebrations and refresh engagement data.
    public var onLoopComplete: (() -> Void)?

    /// Called when the user taps "Continue" on the loop-completion overlay.
    /// The host should wire this to navigate to the next unlocked chapter.
    public var onContinueToNextChapter: (() -> Void)?

    // MARK: - Injected entry points

    /// Called when the user taps "Take the quiz". Set by the host (e.g. AppFeature).
    public var onTakeQuiz: (() -> Void)?

    /// Called when the user taps "Listen". Wired to P6.2 audio by the host.
    public var onListen: (() -> Void)?

    /// Called when the user taps "Ask about this". Wired to P6.1 AI by the host.
    public var onAsk: (() -> Void)?

    /// Called when the user taps "Ask about this" on a specific highlighted passage.
    /// Receives the selected block text as context for the AI query.
    public var onAskAboutSelection: ((String) -> Void)?

    /// Called when the user taps "Book Preferences" in the reader toolbar.
    /// Wired by the host (AppFeature) to present ``BookPreferencesSheet``.
    public var onShowBookPreferences: (() -> Void)?

    /// Async closure that fetches the depth recommendation for `bookId`.
    ///
    /// Injected by the host (AppFeature) using `LiveAIRepository`. When non-nil, the model
    /// fires this after the chapter loads and sets `recommendedVariant` / `recommendedRationale`
    /// on the controls model if the recommendation is confident and the variant is available.
    ///
    /// Failures are silently swallowed — the recommendation is optional chrome.
    public var fetchDepthRecommendation: ((String) async throws -> DepthRecommendation)?

    // MARK: - Annotation

    /// The annotation model for highlights, notes, and bookmarks.
    /// `nil` when no `annotationRepository` was provided at init.
    public private(set) var annotationModel: AnnotationModel?

    // MARK: - Configuration

    public let bookId: String
    public let chapterNumber: Int
    public let variantFamily: VariantFamily

    // MARK: - Internal

    @ObservationIgnored private let repository: any ReaderRepository
    @ObservationIgnored private let annotationRepository: (any AnnotationRepository)?
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let store: KeyValueStore

    /// The chapter number of the last successful cursor PATCH sent to the server.
    /// Used to enforce forward-only semantics.
    @ObservationIgnored private var lastPatchedChapterNumber: Int = 0

    /// The server's reported cursor chapter number at load time.
    /// Initialised from `BookProgress.currentChapterNumber`.
    @ObservationIgnored private var serverCursorChapterNumber: Int = 0

    /// The active reading-session ID assigned by the server on `startReadingSession`.
    @ObservationIgnored private var sessionId: String?

    /// Timestamp of the last scroll activity. Heartbeats are skipped when stale.
    @ObservationIgnored private var lastActivityDate: Date = Date()

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var bookStateTask: Task<Void, Never>?
    @ObservationIgnored private var recommendationTask: Task<Void, Never>?

    /// readPercent threshold above which chapter-end state triggers.
    public static let chapterEndThreshold: Double = 0.95

    /// readPercent threshold above which the quiz CTA appears.
    public static let quizCTAThreshold: Double = 0.85

    /// Seconds of scroll inactivity after which heartbeats are suppressed.
    /// Avoids counting idle time (e.g. user walked away with reader open).
    static let inactivityThreshold: TimeInterval = 60

    // MARK: - Init

    public init(
        bookId: String,
        chapterNumber: Int,
        variantFamily: VariantFamily,
        repository: any ReaderRepository,
        preferences: AppPreferences,
        store: KeyValueStore = KeyValueStore(),
        annotationRepository: (any AnnotationRepository)? = nil
    ) {
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.variantFamily = variantFamily
        self.repository = repository
        self.preferences = preferences
        self.store = store
        self.annotationRepository = annotationRepository
    }

    // MARK: - Lifecycle

    /// Fetches the chapter and constructs the controls model.
    /// Always resets to `.loading` — safe for retry on error.
    public func load() {
        loadTask?.cancel()
        bookStateTask?.cancel()
        recommendationTask?.cancel()
        phase = .loading
        readPercent = 0
        isAtChapterEnd = false
        showQuizCTA = false
        isLoopComplete = false
        isKnowledgeComplete = false
        applicationState = .none
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
    }

    /// Stops heartbeats and fires a best-effort session end + cursor PATCH.
    /// Call from `.onDisappear` on the hosting view.
    public func onDisappear() {
        stopHeartbeats()
        loadTask?.cancel()
        bookStateTask?.cancel()
        recommendationTask?.cancel()
        if case .loaded(let controlsModel) = phase {
            let chapterId = controlsModel.resolvedChapter.chapterId
            let bId = bookId
            let repo = repository
            let sid = sessionId
            Task {
                await repo.endReadingSession(bookId: bId, chapterId: chapterId, sessionId: sid)
            }
            patchCursorIfNeeded(chapterId: chapterId)
        }
    }

    // MARK: - Scroll feedback

    /// Called by the host view when `controlsModel.currentTopBlockIndex` changes.
    ///
    /// Updates progress flags, saves the position, and schedules a cursor PATCH
    /// once the user reaches the chapter end. Also marks reading activity so
    /// heartbeats continue while the user is actively engaged.
    public func didScrollToBlock(_ blockIndex: Int, blockCount: Int, chapterId: String) {
        guard blockCount > 0 else { return }

        lastActivityDate = Date()

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

    // MARK: - Loop completion

    /// Called by the host when the chapter's quiz has been passed.
    ///
    /// Sets `isLoopComplete` (shows the completion overlay in `ReaderView`) and
    /// fires `onLoopComplete` so the host can trigger celebrations and refresh
    /// engagement data from the server.
    public func notifyLoopComplete() {
        isLoopComplete = true
        onLoopComplete?()
    }

    /// Dismisses the loop-completion overlay without navigating away.
    public func dismissLoopComplete() {
        isLoopComplete = false
    }

    // MARK: - Heartbeats

    /// Starts the 30-second heartbeat loop.
    public func startHeartbeats() {
        stopHeartbeats()
        guard case .loaded(let controlsModel) = phase else { return }
        let chapterId = controlsModel.resolvedChapter.chapterId
        let bId = bookId
        let repo = repository
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                // Skip the heartbeat if the reader has been idle for too long.
                let lastActivity = await self?.lastActivityDate ?? Date.distantPast
                guard Date().timeIntervalSince(lastActivity) < Self.inactivityThreshold else { continue }
                let sid = await self?.sessionId
                await repo.postReadingHeartbeat(bookId: bId, chapterId: chapterId, sessionId: sid)
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

            // Derive knowledge-complete from server progress (never computed client-side).
            isKnowledgeComplete = progress.completedChapters.contains(chapterNumber)

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

            // Set up annotation model if a repository was provided.
            if let annotationRepo = annotationRepository {
                let annModel = AnnotationModel(
                    bookId: bookId,
                    chapterId: chapter.chapterId,
                    variantKey: controlsModel.selectedVariant.rawValue,
                    toneKey: controlsModel.selectedTone.rawValue,
                    repository: annotationRepo
                )
                annModel.onAskAboutSelection = { [weak self] text in
                    self?.onAskAboutSelection?(text)
                }
                self.annotationModel = annModel
                Task { await annModel.load() }
            }

            phase = .loaded(controlsModel)
            lastActivityDate = Date()

            // Start session and heartbeats.
            let chapterId = chapter.chapterId
            let bId = bookId
            let repo = repository
            sessionId = await repo.startReadingSession(bookId: bId, chapterId: chapterId)
            startHeartbeats()

            // Fetch book state for the application axis (best-effort, does not block).
            fetchBookState(chapterId: chapterId)

            // Fetch depth recommendation (best-effort, does not block loading).
            applyDepthRecommendation(to: controlsModel)

        } catch is CancellationError {
            // Cancelled — phase remains loading; the next load() call will retry.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Async best-effort fetch of `BookStateResponse` to populate `applicationState`.
    private func fetchBookState(chapterId: String) {
        bookStateTask?.cancel()
        let bId = bookId
        let repo = repository
        bookStateTask = Task { [weak self] in
            guard let self else { return }
            guard let stateResponse = try? await repo.getBookState(bookId: bId) else { return }
            guard !Task.isCancelled else { return }
            self.applicationState = stateResponse.applicationStates?[chapterId] ?? .none
        }
    }

    /// Fires a best-effort depth-recommendation fetch and writes the result onto the
    /// controls model when the recommendation is confident and available.
    ///
    /// Failures are silently swallowed — the recommendation is optional UI chrome.
    private func applyDepthRecommendation(to controlsModel: ReaderControlsModel) {
        guard fetchDepthRecommendation != nil else { return }
        recommendationTask?.cancel()
        let bId = bookId
        let family = variantFamily
        recommendationTask = Task { [weak self] in
            guard let self else { return }
            guard let fetch = self.fetchDepthRecommendation else { return }
            do {
                let rec = try await fetch(bId)
                guard !Task.isCancelled else { return }
                guard rec.isConfident,
                      let depth = rec.recommendedDepth,
                      controlsModel.availableVariants.contains(depth) else { return }
                controlsModel.recommendedVariant = depth
                controlsModel.recommendedRationale = rec.rationale(variantFamily: family)
            } catch {
                // Best-effort — silently ignore recommendation failures.
            }
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
