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
    /// The user is browsing as a guest; prompt sign-in before starting.
    case signInRequired
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

/// Server-authoritative private reading state for Book Detail.
public enum BookDetailPrivateState: Sendable {
    case loading
    case started(
        state: BookUserBookState,
        applicationStates: [String: ChapterApplicationState]
    )
    case notStarted
    case unavailable(UserFacingError)
    case compatibilityUnknown
}

/// Account entitlement state is tracked independently from public metadata and
/// book-state authority so one private request cannot erase a valid book outline.
public enum BookDetailEntitlementState: Sendable {
    case loading
    case available(Entitlement)
    case unavailable(UserFacingError)
    case notRequired
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
        case error(UserFacingError)
    }

    // MARK: - Published state

    public private(set) var loadState: LoadState = .idle
    public private(set) var manifest: BookManifest?
    public private(set) var privateState: BookDetailPrivateState = .loading
    public private(set) var entitlementState: BookDetailEntitlementState = .loading
    /// `true` while `startBook` is in flight.
    public private(set) var isStarting = false
    /// Non-nil when a start action failed.
    public private(set) var startError: UserFacingError?

    /// The server's depth recommendation for this book.
    ///
    /// `nil` until loaded or when `fetchDepthRecommendation` is not wired.
    /// Only show this in the UI when `depthRecommendation?.isConfident == true`.
    public private(set) var depthRecommendation: DepthRecommendation?

    // MARK: - Guest browse mode

    /// When `true`, the model skips the entitlement and book-state fetches so
    /// unauthenticated users can see book metadata and chapter lists. The primary
    /// action becomes `.signInRequired`; tapping it calls `onSignInRequired`.
    public var isGuest: Bool = false

    /// Called when `isGuest == true` and the user taps the primary action
    /// ("Sign in to Read"). Arguments: (bookId, variantFamily). Injected from
    /// AppFeature so LibraryFeature stays decoupled from the auth stack.
    public var onSignInRequired: ((String, VariantFamily) -> Void)?

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
    private let analytics: any AnalyticsClient
    private let evaluator = EntitlementEvaluator()
    @MainActor private var recommendationTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var downloadManager: DownloadManager?
    private var fetchGeneration = 0
    private var privateStateGeneration = 0
    private var entitlementGeneration = 0
    var userId: String = ""

    // MARK: - Init

    public init(
        bookId: String,
        repository: any BookDetailRepository,
        downloadManager: DownloadManager? = nil,
        userId: String = "",
        analytics: any AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.bookId = bookId
        self.repository = repository
        self.downloadManager = downloadManager
        self.userId = userId
        self.analytics = analytics
    }

    // MARK: - Derived: overview

    public var bookState: BookUserBookState? {
        guard case .started(let state, _) = privateState else { return nil }
        return state
    }

    public var applicationStates: [String: ChapterApplicationState] {
        guard case .started(_, let states) = privateState else { return [:] }
        return states
    }

    public var entitlement: Entitlement? {
        guard case .available(let entitlement) = entitlementState else { return nil }
        return entitlement
    }

    public var hasAuthoritativeStartedState: Bool {
        if case .started = privateState { return true }
        return false
    }

    public var hasAuthoritativeProgress: Bool {
        switch privateState {
        case .started, .notStarted:
            return true
        case .loading, .unavailable, .compatibilityUnknown:
            return false
        }
    }

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
        // Guests see the metadata but must sign in before starting.
        if isGuest { return manifest != nil ? .signInRequired : .disabled }
        guard manifest != nil else { return .disabled }

        switch privateState {
        case .started:
            return .continueReading
        case .notStarted:
            guard case .available(let entitlement) = entitlementState else {
                return .disabled
            }
            return evaluator.canStart(bookId: bookId, entitlement: entitlement)
                ? .startReading
                : .showPaywall
        case .loading, .unavailable, .compatibilityUnknown:
            return .disabled
        }
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
        guard hasAuthoritativeStartedState else { return nil }
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

    /// Loads public metadata independently from private state and entitlement.
    /// When `isGuest == true`, only the public manifest is fetched.
    public func fetch() async {
        fetchGeneration &+= 1
        privateStateGeneration &+= 1
        entitlementGeneration &+= 1
        let fetchID = fetchGeneration
        let stateID = privateStateGeneration
        let entitlementID = entitlementGeneration

        loadState = .loading
        privateState = .loading
        entitlementState = isGuest ? .notRequired : .loading

        if isGuest {
            let outcome = await fetchManifestOutcome()
            guard fetchID == fetchGeneration, !Task.isCancelled else { return }
            applyManifest(outcome)
            return
        }

        async let manifestOutcome = fetchManifestOutcome()
        async let stateOutcome = fetchPrivateStateOutcome()
        async let entitlementOutcome = fetchEntitlementOutcome()

        let resolvedManifest = await manifestOutcome
        if fetchID == fetchGeneration, !Task.isCancelled {
            applyManifest(resolvedManifest)
        }

        let resolvedState = await stateOutcome
        if fetchID == fetchGeneration,
           stateID == privateStateGeneration,
           !Task.isCancelled {
            applyPrivateState(resolvedState)
        }

        let resolvedEntitlement = await entitlementOutcome
        if fetchID == fetchGeneration,
           entitlementID == entitlementGeneration,
           !Task.isCancelled {
            applyEntitlement(resolvedEntitlement)
        }
    }

    /// Retries only the private book-state request. Public metadata and a valid
    /// entitlement remain untouched.
    public func retryPrivateState() async {
        guard !isGuest else { return }
        switch privateState {
        case .unavailable, .compatibilityUnknown:
            break
        case .loading, .started, .notStarted:
            return
        }

        let previousState = privateState
        privateStateGeneration &+= 1
        let generation = privateStateGeneration
        privateState = .loading

        let outcome = await fetchPrivateStateOutcome()
        guard generation == privateStateGeneration else { return }
        if Task.isCancelled {
            privateState = previousState
            return
        }
        if case .cancelled = outcome {
            privateState = previousState
            return
        }
        applyPrivateState(outcome)
    }

    /// Retries only a failed entitlement request. Public metadata and book state
    /// remain untouched.
    public func retryEntitlement() async {
        guard !isGuest, case .unavailable = entitlementState else { return }

        let previousState = entitlementState
        entitlementGeneration &+= 1
        let generation = entitlementGeneration
        entitlementState = .loading

        let outcome = await fetchEntitlementOutcome()
        guard generation == entitlementGeneration else { return }
        if Task.isCancelled {
            entitlementState = previousState
            return
        }
        if case .cancelled = outcome {
            entitlementState = previousState
            return
        }
        applyEntitlement(outcome)
    }

    private enum ManifestOutcome: Sendable {
        case value(BookManifest)
        case failure(UserFacingError)
        case cancelled
    }

    private enum PrivateStateOutcome: Sendable {
        case value(BookStateGetResponse)
        case failure(UserFacingError)
        case cancelled
    }

    private enum EntitlementOutcome: Sendable {
        case value(Entitlement)
        case failure(UserFacingError)
        case cancelled
    }

    private func fetchManifestOutcome() async -> ManifestOutcome {
        do {
            return .value(try await repository.getBook(id: bookId))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(UserFacingError.mapping(error)
                ?? UserFacingError(category: .serviceUnavailable))
        }
    }

    private func fetchPrivateStateOutcome() async -> PrivateStateOutcome {
        do {
            return .value(try await repository.getBookState(id: bookId))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(UserFacingError.mapping(error)
                ?? UserFacingError(category: .serviceUnavailable))
        }
    }

    private func fetchEntitlementOutcome() async -> EntitlementOutcome {
        do {
            return .value(try await repository.getEntitlements().entitlement)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(UserFacingError.mapping(error)
                ?? UserFacingError(category: .serviceUnavailable))
        }
    }

    private func applyManifest(_ outcome: ManifestOutcome) {
        switch outcome {
        case .value(let manifest):
            self.manifest = manifest
            loadState = .loaded
            loadDepthRecommendation()
        case .failure(let error):
            loadState = .error(error)
        case .cancelled:
            break
        }
    }

    private func applyPrivateState(_ outcome: PrivateStateOutcome) {
        switch outcome {
        case .value(let response):
            switch response.stateStatus {
            case .started?:
                privateState = .started(
                    state: response.state,
                    applicationStates: response.applicationStates ?? [:]
                )
            case .notStarted?:
                privateState = .notStarted
            case .unknown?, nil:
                privateState = .compatibilityUnknown
            }
        case .failure(let error):
            privateState = .unavailable(error)
        case .cancelled:
            break
        }
    }

    private func applyEntitlement(_ outcome: EntitlementOutcome) {
        switch outcome {
        case .value(let entitlement):
            entitlementState = .available(entitlement)
        case .failure(let error):
            entitlementState = .unavailable(error)
        case .cancelled:
            break
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

    /// Executes the primary action: start, continue, paywall, or sign-in gate.
    public func performPrimaryAction() async {
        switch primaryAction {
        case .signInRequired:
            // Guest mode: delegate to AppFeature to show the auth gate.
            onSignInRequired?(bookId, manifest?.variantFamily ?? .emh)

        case .showPaywall:
            onShowPaywall?()

        case .continueReading:
            onOpenReader?(bookId, currentChapterNumber, manifest?.variantFamily ?? .emh)

        case .startReading:
            guard !isStarting else { return }
            isStarting = true
            startError = nil
            defer { isStarting = false }
            privateStateGeneration &+= 1
            let generation = privateStateGeneration
            do {
                let stateResponse = try await repository.startBook(id: bookId)
                guard !Task.isCancelled, generation == privateStateGeneration else { return }
                privateState = .started(
                    state: stateResponse.state,
                    applicationStates: stateResponse.applicationStates ?? [:]
                )
                analytics.track(.bookStarted(bookId: bookId))
                // Navigate to the first unlocked chapter (typically ch. 1).
                onOpenReader?(bookId, currentChapterNumber, manifest?.variantFamily ?? .emh)
            } catch is CancellationError {
                return
            } catch {
                guard generation == privateStateGeneration else { return }
                startError = UserFacingError.mapping(error)
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
        guard hasAuthoritativeStartedState,
              let manager = downloadManager,
              !userId.isEmpty else { return }
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
