import Foundation
import SwiftData
import Models
import Networking
import Persistence
import os

// MARK: - Background URLSession download bridge

/// A `URLSessionDownloadDelegate`-based session bridge that converts completion
/// callbacks into Swift async continuations.  Audio segment files are moved to
/// their final `FileStore` location inside the delegate method so the temp file
/// is never deleted before it can be read.
private final class SegmentDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias SegmentContinuation = CheckedContinuation<Void, any Error>

    private struct PendingTask {
        let continuation: SegmentContinuation
        let destURL: URL
    }

    nonisolated(unsafe) private var pending: [Int: PendingTask] = [:]
    private let lock = NSLock()

    lazy var urlSession: URLSession = {
        let id = "com.chapterflow.ios.audio-segment-dl"
        var config = URLSessionConfiguration.background(withIdentifier: id)
        config.networkServiceType = .responsiveAV
        config.waitsForConnectivity = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Downloads `url` and atomically moves the result to `destURL`.
    func download(from url: URL, to destURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: SegmentContinuation) in
            let task = urlSession.downloadTask(with: url)
            lock.lock()
            pending[task.taskIdentifier] = PendingTask(continuation: continuation, destURL: destURL)
            lock.unlock()
            task.resume()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let entry = pending.removeValue(forKey: downloadTask.taskIdentifier)
        lock.unlock()
        guard let entry else { return }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: entry.destURL.path) {
                try fm.removeItem(at: entry.destURL)
            }
            try fm.moveItem(at: location, to: entry.destURL)
            entry.continuation.resume()
        } catch {
            entry.continuation.resume(throwing: error)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else { return }
        lock.lock()
        let entry = pending.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        entry?.continuation.resume(throwing: error)
    }
}

// MARK: - DownloadManager

/// An actor that manages book downloads: fetches manifests, chapters, quizzes,
/// and audio segments; stores them in SwiftData / FileStore; tracks progress via
/// `AsyncStream`; and enforces a configurable storage cap with LRU eviction.
///
/// Conforms to `DownloadInfoProviding` so the Settings screen can query and
/// delete downloads without taking a dependency on the full actor.
public actor DownloadManager: DownloadInfoProviding {

    // MARK: - Dependencies

    let container: ModelContainer
    let fileStore: FileStore
    let apiClient: any APIClientProtocol
    let preferences: AppPreferences
    private let segmentSession: SegmentDownloadSession

    // MARK: - Active task registry

    var activeTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Logger

    let logger = Logger(subsystem: "com.chapterflow.ios", category: "DownloadManager")

    // MARK: - Init

    public init(
        container: ModelContainer,
        fileStore: FileStore,
        apiClient: any APIClientProtocol,
        preferences: AppPreferences
    ) {
        self.container = container
        self.fileStore = fileStore
        self.apiClient = apiClient
        self.preferences = preferences
        self.segmentSession = SegmentDownloadSession()
    }

    // MARK: - Public API

    /// Starts (or resumes) a book download and returns a stream of progress events.
    ///
    /// If a download is already in progress for this book, the existing task is
    /// cancelled and a new one replaces it.
    public func downloadBook(bookId: String, userId: String) -> AsyncStream<DownloadProgress> {
        activeTasks[bookId]?.cancel()

        return AsyncStream { [weak self] continuation in
            guard let self else { return }
            let task: Task<Void, Never> = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.performDownload(
                        bookId: bookId,
                        userId: userId,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(DownloadProgress(
                        bookId: bookId,
                        phase: .failed(error.localizedDescription),
                        fractionCompleted: 0
                    ))
                    continuation.finish()
                }
            }
            Task { [weak self] in
                await self?.storeTask(task, for: bookId)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.cancelDownload(bookId: bookId, userId: userId) }
            }
        }
    }

    private func storeTask(_ task: Task<Void, Never>, for bookId: String) {
        activeTasks[bookId] = task
    }

    /// Cancels an in-progress download and marks it failed in the store.
    public func cancelDownload(bookId: String, userId: String) async {
        activeTasks[bookId]?.cancel()
        activeTasks.removeValue(forKey: bookId)
        let bg = BackgroundStore(modelContainer: container)
        try? await bg.markDownloadFailed(bookId: bookId, userId: userId, message: "Cancelled")
    }

    // MARK: - DownloadInfoProviding

    public func downloadedBooks(userId: String) async -> [DownloadedBookInfo] {
        let bg = BackgroundStore(modelContainer: container)
        return (try? await bg.fetchDownloadedBooks(userId: userId)) ?? []
    }

    public func totalUsedBytes(userId: String) async -> Int64 {
        let bg = BackgroundStore(modelContainer: container)
        return (try? await bg.totalDownloadBytes(userId: userId)) ?? 0
    }

    public func isDownloaded(bookId: String, userId: String) async -> Bool {
        let bg = BackgroundStore(modelContainer: container)
        return (try? await bg.isDownloaded(bookId: bookId, userId: userId)) ?? false
    }

    public func deleteBookDownload(bookId: String, userId: String) async throws {
        activeTasks[bookId]?.cancel()
        activeTasks.removeValue(forKey: bookId)
        let bg = BackgroundStore(modelContainer: container)
        let segmentIds = try await bg.segmentIds(bookId: bookId, userId: userId)
        for segId in segmentIds {
            try? fileStore.remove(named: CachedDownloadedSegment.fileStoreKey(segmentId: segId))
        }
        try await bg.deleteBookDownloadRecords(bookId: bookId, userId: userId)
    }

    public func deleteAllBookDownloads(userId: String) async throws {
        let bg = BackgroundStore(modelContainer: container)
        let books = (try? await bg.fetchDownloadedBooks(userId: userId)) ?? []
        for book in books {
            try? await deleteBookDownload(bookId: book.bookId, userId: userId)
        }
    }

    // MARK: - Storage accounting + eviction

    /// Enforces the storage cap by evicting the oldest completed downloads (LRU).
    public func enforceStorageCap(userId: String) async {
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
        try await bg.upsertChapter(response.chapter, userId: userId, bookId: bookId)

        // Quiz
        do {
            let quizResponse: QuizResponse = try await apiClient.send(
                Endpoints.getQuizForDownload(bookId: bookId, chapterNumber: chapterNumber)
            )
            try await bg.upsertQuiz(
                quizResponse.quiz, userId: userId, bookId: bookId, chapterNumber: chapterNumber
            )
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

public enum DownloadError: LocalizedError {
    case wifiRequired

    public var errorDescription: String? {
        switch self {
        case .wifiRequired:
            return "Download over Wi-Fi required. Connect to Wi-Fi or disable the Wi-Fi-only setting."
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
