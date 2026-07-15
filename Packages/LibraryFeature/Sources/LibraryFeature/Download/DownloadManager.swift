import Foundation
import SwiftData
import Models
import Networking
import Persistence
import CoreKit
import os

// MARK: - DownloadManager

enum DownloadManagerLifecycleState: Sendable, Equatable {
    case active
    case paused
    case invalidated
}

struct DownloadManagerLifecycleSnapshot: Sendable, Equatable {
    let state: DownloadManagerLifecycleState
    let activeTaskCount: Int
}

/// An actor that manages book downloads: fetches manifests, chapters, quizzes,
/// and audio segments; stores them in SwiftData / FileStore; tracks progress via
/// `AsyncStream`; and enforces a configurable storage cap with LRU eviction.
///
/// Conforms to `DownloadInfoProviding` so the Settings screen can query and
/// delete downloads without taking a dependency on the full actor.
public actor DownloadManager: DownloadInfoProviding {

    typealias DownloadOperation = @Sendable (
        _ bookID: String,
        _ userID: String,
        _ continuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> Void

    // MARK: - Dependencies

    let container: ModelContainer
    let fileStore: FileStore
    let apiClient: any APIClientProtocol
    let preferences: AppPreferences
    private let workPermit: SessionWorkPermit
    private let segmentSession: any SegmentDownloading
    private let downloadOperation: DownloadOperation?
    private let beforeDeleteCommit: (@Sendable () async -> Void)?
    private let deleteCommitObserver: (@Sendable () -> Void)?

    /// Privacy-safe identifier for the account-bound background URLSession.
    public nonisolated let backgroundSessionIdentifier: String

    // MARK: - Active task registry

    var activeTasks: [String: Task<Void, Never>] = [:]
    private var activeTaskIDs: [String: UUID] = [:]
    private var lifecycleState: DownloadManagerLifecycleState = .active

    var acceptsNewWork: Bool { lifecycleState == .active }

    // MARK: - Logger

    let logger = Logger(subsystem: "com.chapterflow.ios", category: "DownloadManager")

    // MARK: - Init

    public init(
        resources: AccountPersistenceResources,
        apiClient: any APIClientProtocol,
        preferences: AppPreferences,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        let segmentSession = SegmentDownloadSession(
            accountNamespace: resources.storageNamespace
        )
        self.container = resources.controller.container
        self.fileStore = resources.downloadFileStore
        self.apiClient = apiClient
        self.preferences = preferences
        self.workPermit = workPermit
        self.segmentSession = segmentSession
        self.downloadOperation = nil
        self.beforeDeleteCommit = nil
        self.deleteCommitObserver = nil
        self.backgroundSessionIdentifier = segmentSession.sessionIdentifier
    }

    init(
        resources: AccountPersistenceResources,
        apiClient: any APIClientProtocol,
        preferences: AppPreferences,
        segmentSession: any SegmentDownloading,
        downloadOperation: DownloadOperation?,
        beforeDeleteCommit: (@Sendable () async -> Void)? = nil,
        deleteCommitObserver: (@Sendable () -> Void)? = nil,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        self.container = resources.controller.container
        self.fileStore = resources.downloadFileStore
        self.apiClient = apiClient
        self.preferences = preferences
        self.segmentSession = segmentSession
        self.downloadOperation = downloadOperation
        self.beforeDeleteCommit = beforeDeleteCommit
        self.deleteCommitObserver = deleteCommitObserver
        self.workPermit = workPermit
        self.backgroundSessionIdentifier = segmentSession.sessionIdentifier
    }

    var lifecycleSnapshotForTesting: DownloadManagerLifecycleSnapshot {
        DownloadManagerLifecycleSnapshot(
            state: lifecycleState,
            activeTaskCount: activeTasks.count
        )
    }

    // MARK: - Account lifetime

    /// Cancels and awaits every tracked download while continuing to accept future work.
    public func cancelAll() async {
        guard lifecycleState != .invalidated else { return }
        await cancelAndAwaitActiveTasks(invalidateSegmentSession: false)
    }

    /// Quiesces this account's downloads. Durable records and files are retained.
    public func pause() async {
        guard lifecycleState == .active else { return }
        lifecycleState = .paused
        workPermit.quiesce()
        await cancelAndAwaitActiveTasks(invalidateSegmentSession: false)
    }

    /// Resumes this same account's manager after a reversible pause.
    public func resume() {
        guard lifecycleState == .paused else { return }
        workPermit.resume()
        lifecycleState = .active
    }

    /// Permanently invalidates this account manager and rejects all future work.
    public func invalidate() async {
        guard lifecycleState != .invalidated else { return }
        lifecycleState = .invalidated
        workPermit.invalidate()
        await cancelAndAwaitActiveTasks(invalidateSegmentSession: true)
    }

    // MARK: - Public API

    /// Starts (or resumes) a book download and returns a stream of progress events.
    ///
    /// If a download is already in progress for this book, the existing task is
    /// cancelled and a new one replaces it.
    public func downloadBook(bookId: String, userId: String) async -> AsyncStream<DownloadProgress> {
        guard lifecycleState == .active else {
            return inactiveProgressStream(bookId: bookId)
        }

        if let existing = activeTasks.removeValue(forKey: bookId) {
            activeTaskIDs.removeValue(forKey: bookId)
            existing.cancel()
            await existing.value
        }

        let stream = AsyncStream<DownloadProgress>.makeStream()
        let taskID = UUID()
        let operation = downloadOperation
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else {
                stream.continuation.finish()
                return
            }
            do {
                if let operation {
                    try await operation(bookId, userId, stream.continuation)
                } else {
                    try await self.performDownload(
                        bookId: bookId,
                        userId: userId,
                        continuation: stream.continuation
                    )
                }
                stream.continuation.finish()
            } catch is CancellationError {
                stream.continuation.finish()
            } catch {
                stream.continuation.yield(DownloadProgress(
                    bookId: bookId,
                    phase: .failed(error.localizedDescription),
                    fractionCompleted: 0
                ))
                stream.continuation.finish()
            }
            await self.downloadTaskDidFinish(bookId: bookId, taskID: taskID)
        }
        activeTasks[bookId] = task
        activeTaskIDs[bookId] = taskID
        stream.continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.cancelDownload(bookId: bookId, userId: userId) }
        }
        return stream.stream
    }

    /// Cancels an in-progress download and marks it failed in the store.
    public func cancelDownload(bookId: String, userId: String) async {
        let task = activeTasks.removeValue(forKey: bookId)
        activeTaskIDs.removeValue(forKey: bookId)
        task?.cancel()
        await task?.value
        guard lifecycleState == .active else { return }
        let bg = BackgroundStore(modelContainer: container)
        try? await bg.markDownloadFailed(bookId: bookId, userId: userId, message: "Cancelled")
    }

    private func cancelAndAwaitActiveTasks(invalidateSegmentSession: Bool) async {
        let retainedTasks = Array(activeTasks.values)
        activeTasks.removeAll()
        activeTaskIDs.removeAll()
        retainedTasks.forEach { $0.cancel() }

        if invalidateSegmentSession {
            await segmentSession.invalidate()
        } else {
            await segmentSession.cancelAll()
        }

        for task in retainedTasks {
            await task.value
        }
    }

    private func downloadTaskDidFinish(bookId: String, taskID: UUID) {
        guard activeTaskIDs[bookId] == taskID else { return }
        activeTaskIDs.removeValue(forKey: bookId)
        activeTasks.removeValue(forKey: bookId)
    }

    private func inactiveProgressStream(bookId: String) -> AsyncStream<DownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(DownloadProgress(
                bookId: bookId,
                phase: .failed(DownloadError.inactive.localizedDescription),
                fractionCompleted: 0
            ))
            continuation.finish()
        }
    }

    // MARK: - DownloadInfoProviding

    public func downloadedBooks(userId: String) async -> [DownloadedBookInfo] {
        guard lifecycleState == .active else { return [] }
        let bg = BackgroundStore(modelContainer: container)
        return (try? await bg.fetchDownloadedBooks(userId: userId)) ?? []
    }

    public func totalUsedBytes(userId: String) async -> Int64 {
        guard lifecycleState == .active else { return 0 }
        let bg = BackgroundStore(modelContainer: container)
        return (try? await bg.totalDownloadBytes(userId: userId)) ?? 0
    }

    public func isDownloaded(bookId: String, userId: String) async -> Bool {
        guard lifecycleState == .active else { return false }
        let bg = BackgroundStore(modelContainer: container)
        return (try? await bg.isDownloaded(bookId: bookId, userId: userId)) ?? false
    }

    public func deleteBookDownload(bookId: String, userId: String) async throws {
        guard lifecycleState == .active else { throw DownloadError.inactive }
        let ticket = try workPermit.begin()
        let task = activeTasks.removeValue(forKey: bookId)
        activeTaskIDs.removeValue(forKey: bookId)
        task?.cancel()
        await task?.value
        let bg = BackgroundStore(modelContainer: container)
        let segmentIds = try await bg.segmentIds(bookId: bookId, userId: userId)
        await beforeDeleteCommit?()
        try workPermit.commit(ticket) {
            guard lifecycleState == .active else { throw DownloadError.inactive }
            deleteCommitObserver?()
            for segmentID in segmentIds {
                try? fileStore.remove(
                    named: CachedDownloadedSegment.fileStoreKey(segmentId: segmentID)
                )
            }
            try deleteBookDownloadRecords(bookId: bookId, userId: userId)
        }
    }

    public func deleteAllBookDownloads(userId: String) async throws {
        guard lifecycleState == .active else { throw DownloadError.inactive }
        let bg = BackgroundStore(modelContainer: container)
        let books = (try? await bg.fetchDownloadedBooks(userId: userId)) ?? []
        for book in books {
            try? await deleteBookDownload(bookId: book.bookId, userId: userId)
        }
    }

    private func deleteBookDownloadRecords(bookId: String, userId: String) throws {
        let context = ModelContext(container)
        do {
            let uid = userId
            let bid = bookId
            try context.delete(
                model: CachedDownloadedSegment.self,
                where: #Predicate { $0.bookId == bid && $0.userId == uid }
            )
            let rowID = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
            let descriptor = FetchDescriptor<CachedBookDownload>(
                predicate: #Predicate { $0.rowId == rowID }
            )
            if let record = try context.fetch(descriptor).first {
                context.delete(record)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Storage accounting + eviction

    /// Enforces the storage cap by evicting the oldest completed downloads (LRU).
    public func enforceStorageCap(userId: String) async {
        guard lifecycleState == .active else { return }
        guard let limitBytes = await MainActor.run(body: { preferences.downloadStorageLimitBytes })
        else { return }
        let total = await totalUsedBytes(userId: userId)
        guard total > limitBytes else { return }
        let bg = BackgroundStore(modelContainer: container)
        guard let downloads = try? await bg.allCompletedDownloads(userId: userId) else { return }
        let sorted = downloads.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        var remaining = total
        for download in sorted {
            guard remaining > limitBytes else { break }
            let freed = download.totalBytes
            try? await deleteBookDownload(bookId: download.bookId, userId: userId)
            remaining -= freed
            logger.info("Evicted \(download.bookId) (\(freed) bytes) — cap enforcement")
        }
    }

    // MARK: - Download orchestration

    private func performDownload(
        bookId: String,
        userId: String,
        continuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws {
        try Task.checkCancellation()

        // Wifi-only check
        let wifiOnly = await MainActor.run { preferences.downloadOverWifiOnly }
        if wifiOnly {
            let onWifi = NetworkReachability.isOnWifi()
            guard onWifi else {
                throw DownloadError.wifiRequired
            }
        }

        // 1. Manifest
        continuation.yield(DownloadProgress(
            bookId: bookId, phase: .fetchingManifest, fractionCompleted: 0
        ))
        let manifest: BookManifest = try await apiClient.send(
            Endpoints.getManifestForDownload(bookId: bookId)
        )
        try Task.checkCancellation()
        let bg = BackgroundStore(modelContainer: container)
        try await bg.upsertManifest(manifest, userId: userId)

        // Create or reset the CachedBookDownload record
        let chapterCount = manifest.chapters.count
        try await bg.upsertBookDownload(
            bookId: bookId,
            userId: userId,
            title: manifest.title,
            chapterCount: chapterCount
        )

        try Task.checkCancellation()

        // 2. Chapters + quizzes
        for (idx, chapter) in manifest.chapters.enumerated() {
            try Task.checkCancellation()
            let fraction = Double(idx) / Double(max(1, chapterCount)) * 0.5
            continuation.yield(DownloadProgress(
                bookId: bookId,
                phase: .downloadingChapters(current: idx + 1, total: chapterCount),
                fractionCompleted: fraction
            ))
            try await downloadChapter(
                bookId: bookId,
                chapterNumber: chapter.number,
                userId: userId,
                bg: bg
            )
            try await bg.incrementDownloadedChapters(bookId: bookId, userId: userId)
        }

        try Task.checkCancellation()

        // 3. Audio segments (resume-aware)
        try await downloadAudioPhase(
            bookId: bookId, userId: userId, manifest: manifest, bg: bg, continuation: continuation
        )

        try Task.checkCancellation()

        // Mark complete
        try await bg.markDownloadComplete(bookId: bookId, userId: userId)
        continuation.yield(DownloadProgress(bookId: bookId, phase: .complete, fractionCompleted: 1))

        // Enforce cap after successful download
        await enforceStorageCap(userId: userId)
    }

    private func downloadAudioPhase(
        bookId: String,
        userId: String,
        manifest: BookManifest,
        bg: BackgroundStore,
        continuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws {
        let storedSegIds = Set(try await bg.segmentIds(bookId: bookId, userId: userId))
        var allSegmentCount = 0
        var segmentsToFetch: [(chapterNumber: Int, segment: AudioSegment)] = []

        for chapter in manifest.chapters {
            try Task.checkCancellation()
            let plan: AudioNarrationResponse = try await apiClient.send(
                Endpoints.getAudioPlanFreshURLs(bookId: bookId, chapterNumber: chapter.number)
            )
            for seg in plan.plan.segments {
                allSegmentCount += 1
                if !storedSegIds.contains(seg.segmentId) {
                    segmentsToFetch.append((chapter.number, seg))
                }
            }
        }

        try await bg.setAudioSegmentCount(bookId: bookId, userId: userId, count: allSegmentCount)
        let alreadyDownloaded = allSegmentCount - segmentsToFetch.count
        if alreadyDownloaded > 0 {
            try await bg.setDownloadedAudioSegmentCount(
                bookId: bookId, userId: userId, count: alreadyDownloaded
            )
        }

        for (idx, entry) in segmentsToFetch.enumerated() {
            try Task.checkCancellation()
            let done = alreadyDownloaded + idx
            let fraction = 0.5 + Double(done) / Double(max(1, allSegmentCount)) * 0.5
            continuation.yield(DownloadProgress(
                bookId: bookId,
                phase: .downloadingAudio(current: done + 1, total: allSegmentCount),
                fractionCompleted: fraction
            ))
            try await downloadSegment(
                segment: entry.segment,
                bookId: bookId,
                chapterNumber: entry.chapterNumber,
                userId: userId,
                bg: bg
            )
            try await bg.incrementDownloadedSegments(bookId: bookId, userId: userId)
        }
    }

    func downloadChapter(
        bookId: String,
        chapterNumber: Int,
        userId: String,
        bg: BackgroundStore
    ) async throws {
        let response: ChapterResponse = try await apiClient.send(
            Endpoints.getChapterForDownload(bookId: bookId, chapterNumber: chapterNumber)
        )
        try Task.checkCancellation()
        try await bg.upsertChapter(response.chapter, userId: userId, bookId: bookId)

        // Quiz
        do {
            let quizResponse: QuizResponse = try await apiClient.send(
                Endpoints.getQuizForDownload(bookId: bookId, chapterNumber: chapterNumber)
            )
            try Task.checkCancellation()
            try await bg.upsertQuiz(
                quizResponse.quiz, userId: userId, bookId: bookId, chapterNumber: chapterNumber
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Quiz may not exist for every chapter — log and continue
            logger.info("No quiz for chapter \(chapterNumber) of \(bookId): \(error)")
        }

        // Accumulate bytes for the chapter JSON
        let chapterData = try JSONEncoder().encode(response.chapter)
        try await bg.addBytes(bookId: bookId, userId: userId, bytes: Int64(chapterData.count))
    }

    private func downloadSegment(
        segment: AudioSegment,
        bookId: String,
        chapterNumber: Int,
        userId: String,
        bg: BackgroundStore
    ) async throws {
        let fileKey = CachedDownloadedSegment.fileStoreKey(segmentId: segment.segmentId)
        let destURL = fileStore.url(for: fileKey)
        try await segmentSession.download(from: segment.url, to: destURL)
        try Task.checkCancellation()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
        try await bg.insertDownloadedSegment(
            segmentId: segment.segmentId,
            bookId: bookId,
            chapterNumber: chapterNumber,
            userId: userId,
            fileSize: fileSize
        )
        try await bg.addBytes(bookId: bookId, userId: userId, bytes: fileSize)
    }
}

// MARK: - Download errors

public enum DownloadError: LocalizedError, Sendable {
    case wifiRequired
    case inactive

    public var errorDescription: String? {
        switch self {
        case .wifiRequired:
            return "Download over Wi-Fi required. Connect to Wi-Fi or disable the Wi-Fi-only setting."
        case .inactive:
            return "Downloads are unavailable for this session."
        }
    }
}

// MARK: - NetworkReachability helper

private enum NetworkReachability {
    static func isOnWifi() -> Bool {
        // A lightweight check using getifaddrs is sufficient here;
        // a full NWPathMonitor integration belongs in a future CoreKit module.
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            let name = String(cString: addr.pointee.ifa_name)
            if name.hasPrefix("en") { return true }  // en0 = Wi-Fi on iOS
            current = addr.pointee.ifa_next
        }
        return false
    }
}
