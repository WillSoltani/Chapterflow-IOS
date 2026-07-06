import Foundation
import Observation
import Models
import CoreKit
import Persistence

// MARK: - Supporting types

/// The primary call-to-action the book detail screen should present.
public enum BookDetailPrimaryAction: Equatable {
    /// The book hasn't been started; call `startBook` then navigate to chapter 1.
    case startReading
    /// The book is in progress; navigate directly to the current chapter.
    case continueReading
    /// The user has no access; open the paywall.
    case showPaywall
    /// Data is still loading; disable the button.
    case disabled
}

/// Why a chapter is currently inaccessible.
public enum ChapterLockReason: Equatable {
    /// The user must finish the prior chapter's quiz to unlock this one.
    case finishPriorQuiz
    /// The chapter requires a Pro subscription.
    case requiresPro
}

// MARK: - BookDetailModel

/// Observable model driving ``BookDetailView``.
///
/// Fetches the book manifest, per-book reading state, and current entitlement
/// concurrently. Derives chapter lock/complete states from server-authoritative data —
/// nothing is written client-side.
@Observable
@MainActor
public final class BookDetailModel {

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - Published state

    public private(set) var loadState: LoadState = .idle
    public private(set) var manifest: BookManifest?
    public private(set) var bookState: BookUserBookState?
    public private(set) var applicationStates: [String: ChapterApplicationState] = [:]
    public private(set) var entitlement: Entitlement?
    /// `true` while `startBook` is in flight.
    public private(set) var isStarting = false
    /// Non-nil when a start action failed.
    public private(set) var startError: String?

    /// The server's depth recommendation for this book.
    ///
    /// `nil` until loaded or when `fetchDepthRecommendation` is not wired.
    /// Only show this in the UI when `depthRecommendation?.isConfident == true`.
    public private(set) var depthRecommendation: DepthRecommendation?

    // MARK: - Navigation callbacks (injected from AppFeature)

    /// Called when the user taps Start/Continue and the book can be opened.
    /// Arguments: (bookId, chapterNumber, variantFamily).
    public var onOpenReader: ((String, Int, VariantFamily) -> Void)?
    /// Called when the user taps Start but has no access — show the paywall.
    public var onShowPaywall: (() -> Void)?

    /// Async closure that fetches a depth recommendation for `bookId`.
    ///
    /// Wired by the host (`BookDetailView`) using the `AIRepository`. Failures are
    /// silently swallowed — the recommendation is optional UI chrome.
    public var fetchDepthRecommendation: ((String) async throws -> DepthRecommendation)?

    // MARK: - Download state

    /// Current offline-availability state of this book.
    public private(set) var downloadState: DownloadButtonState = .notDownloaded

    // MARK: - Private

    public let bookId: String
    private let repository: any BookDetailRepository
    private let evaluator = EntitlementEvaluator()
    @MainActor private var recommendationTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var downloadManager: DownloadManager?
    var userId: String = ""

    // MARK: - Init

    public init(
        bookId: String,
        repository: any BookDetailRepository,
        downloadManager: DownloadManager? = nil,
        userId: String = ""
    ) {
        self.bookId = bookId
        self.repository = repository
        self.downloadManager = downloadManager
        self.userId = userId
    }

    // MARK: - Derived: overview

    public var totalChapters: Int { manifest?.chapters.count ?? 0 }

    public var completedChapterCount: Int { bookState?.completedChapterIds.count ?? 0 }

    public var progressFraction: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(completedChapterCount) / Double(totalChapters)
    }

    /// How many free book starts the user has remaining. Zero before entitlement loads.
    public var freeStartsLeft: Int { entitlement?.remainingFreeStarts ?? 0 }

    /// Reading-time sum for the whole book (minutes).
    public var totalReadingMinutes: Int {
        manifest?.chapters.reduce(0) { $0 + $1.readingTimeMinutes } ?? 0
    }

    // MARK: - Derived: primary action

    public var primaryAction: BookDetailPrimaryAction {
        guard let entitlement else { return .disabled }
        if bookState != nil { return .continueReading }
        return evaluator.canStart(bookId: bookId, entitlement: entitlement)
            ? .startReading
            : .showPaywall
    }

    /// The chapter number the reader should open at (1-based).
    public var currentChapterNumber: Int {
        guard let bookState else { return 1 }
        let targetId = bookState.currentChapterId ?? bookState.lastReadChapterId
        guard let chapterId = targetId,
              let chapter = manifest?.chapters.first(where: { $0.chapterId == chapterId })
        else { return 1 }
        return chapter.number
    }

    // MARK: - Derived: per-chapter

    /// Whether the server has granted the user access to this chapter.
    public func isUnlocked(_ chapter: BookManifestChapter) -> Bool {
        bookState?.unlockedChapterIds.contains(chapter.chapterId) ?? false
    }

    public func isCompleted(_ chapter: BookManifestChapter) -> Bool {
        bookState?.completedChapterIds.contains(chapter.chapterId) ?? false
    }

    /// Best quiz score for this chapter (0–100), or `nil` if not yet attempted.
    public func score(_ chapter: BookManifestChapter) -> Int? {
        bookState?.chapterScores[chapter.chapterId]
    }

    /// Application-axis state (committed / applied / none).
    public func applicationState(_ chapter: BookManifestChapter) -> ChapterApplicationState {
        applicationStates[chapter.chapterId] ?? .none
    }

    /// Why a locked chapter is inaccessible. Returns `nil` for unlocked chapters.
    public func lockReason(_ chapter: BookManifestChapter) -> ChapterLockReason? {
        guard !isUnlocked(chapter) else { return nil }
        guard let chapters = manifest?.chapters else { return .requiresPro }
        // Chapter 1 should never be locked once the book is started;
        // treat it as Pro-gated to be safe.
        guard chapter.number > 1 else { return .requiresPro }
        // If the prior chapter hasn't been completed, the user needs to finish its quiz.
        if let prior = chapters.first(where: { $0.number == chapter.number - 1 }),
           !isCompleted(prior) {
            return .finishPriorQuiz
        }
        return .requiresPro
    }

    // MARK: - Actions

    /// Loads manifest, state, and entitlements concurrently.
    /// Gracefully handles a `.notFound` on the state endpoint (book not yet started).
    public func fetch() async {
        loadState = .loading
        do {
            async let manifestTask = repository.getBook(id: bookId)
            async let entitlementTask = repository.getEntitlements()
            let (fetchedManifest, entitlementResponse) = try await (manifestTask, entitlementTask)

            // State returns .notFound for books the user hasn't started — treat as nil.
            let stateResponse: BookStateResponse?
            do {
                stateResponse = try await repository.getBookState(id: bookId)
            } catch AppError.notFound {
                stateResponse = nil
            } catch {
                stateResponse = nil
            }

            self.manifest = fetchedManifest
            self.entitlement = entitlementResponse.entitlement
            self.bookState = stateResponse?.state
            self.applicationStates = stateResponse?.applicationStates ?? [:]
            self.loadState = .loaded

            // Fire depth recommendation fetch (best-effort, non-blocking).
            loadDepthRecommendation()

        } catch let appErr as AppError {
            loadState = .error(appErr.errorDescription ?? appErr.code)
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// Fires a best-effort depth recommendation fetch and stores the result.
    ///
    /// Only stores the recommendation when confidence is sufficient; silently
    /// discards errors and low-confidence responses.
    private func loadDepthRecommendation() {
        guard fetchDepthRecommendation != nil else { return }
        recommendationTask?.cancel()
        let bId = bookId
        recommendationTask = Task { [weak self] in
            guard let self else { return }
            guard let fetch = self.fetchDepthRecommendation else { return }
            do {
                let rec = try await fetch(bId)
                guard !Task.isCancelled else { return }
                self.depthRecommendation = rec.isConfident ? rec : nil
            } catch {
                // Best-effort — recommendation failure never affects the main view state.
            }
        }
    }

    /// Executes the primary action: start, continue, or paywall.
    public func performPrimaryAction() async {
        switch primaryAction {
        case .showPaywall:
            onShowPaywall?()

        case .continueReading:
            onOpenReader?(bookId, currentChapterNumber, manifest?.variantFamily ?? .emh)

        case .startReading:
            isStarting = true
            startError = nil
            defer { isStarting = false }
            do {
                let stateResponse = try await repository.startBook(id: bookId)
                bookState = stateResponse.state
                applicationStates = stateResponse.applicationStates ?? [:]
                // Navigate to the first unlocked chapter (typically ch. 1).
                onOpenReader?(bookId, currentChapterNumber, manifest?.variantFamily ?? .emh)
            } catch let appErr as AppError {
                startError = appErr.errorDescription ?? appErr.code
            } catch {
                startError = error.localizedDescription
            }

        case .disabled:
            break
        }
    }

    /// Navigates to an unlocked chapter; no-ops for locked ones.
    public func tapChapter(_ chapter: BookManifestChapter) {
        guard isUnlocked(chapter) else { return }
        onOpenReader?(bookId, chapter.number, manifest?.variantFamily ?? .emh)
    }

    // MARK: - Download actions

    /// Checks the stored download state and updates `downloadState`.
    public func refreshDownloadState() async {
        guard let manager = downloadManager, !userId.isEmpty else { return }
        let isOffline = await manager.isDownloaded(bookId: bookId, userId: userId)
        downloadState = isOffline ? .downloaded : .notDownloaded
    }

    /// Begins or resumes a download, updating `downloadState` as events arrive.
    public func startDownload() {
        guard let manager = downloadManager, !userId.isEmpty else { return }
        downloadTask?.cancel()
        let bid = bookId
        let uid = userId
        downloadTask = Task { [weak self] in
            guard let self else { return }
            let stream = await manager.downloadBook(bookId: bid, userId: uid)
            for await progress in stream {
                guard !Task.isCancelled else { break }
                switch progress.phase {
                case .fetchingManifest, .downloadingChapters, .downloadingAudio:
                    self.downloadState = .inProgress(fraction: progress.fractionCompleted)
                case .complete:
                    self.downloadState = .downloaded
                case .failed(let msg):
                    self.downloadState = .failed(msg)
                }
            }
        }
    }

    /// Cancels an in-progress download.
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .notDownloaded
        guard let manager = downloadManager, !userId.isEmpty else { return }
        Task { await manager.cancelDownload(bookId: bookId, userId: userId) }
    }

    /// Deletes the stored download.
    public func deleteDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .notDownloaded
        guard let manager = downloadManager, !userId.isEmpty else { return }
        Task {
            try? await manager.deleteBookDownload(bookId: bookId, userId: userId)
        }
    }
}
