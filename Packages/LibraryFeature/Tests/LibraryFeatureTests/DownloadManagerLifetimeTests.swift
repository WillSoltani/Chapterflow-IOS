import Foundation
import CoreKit
import Networking
import Persistence
import Testing
@testable import LibraryFeature

private actor SegmentDownloaderProbe: SegmentDownloading {
    nonisolated let sessionIdentifier: String
    private(set) var cancelAllCount = 0
    private(set) var invalidateCount = 0

    init(sessionIdentifier: String = "test.segment.session") {
        self.sessionIdentifier = sessionIdentifier
    }

    func download(from url: URL, to destination: URL) async throws {}
    func cancelAll() async { cancelAllCount += 1 }
    func invalidate() async { invalidateCount += 1 }
}

private actor InvalidationCompletionProbe {
    private(set) var didComplete = false

    func markComplete() {
        didComplete = true
    }
}

private struct ControlledDownloadOperation: Sendable {
    let started = AsyncStream<Void>.makeStream()

    func run() async throws {
        started.continuation.yield(())
        let blocker = AsyncStream<Void>.makeStream()
        await withTaskCancellationHandler {
            for await _ in blocker.stream {}
        } onCancel: {
            blocker.continuation.finish()
        }
        try Task.checkCancellation()
    }
}

private actor DeletePreparationGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func block() async {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
            }
        }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private final class DeleteCommitProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var committed = false

    func markCommitted() {
        lock.withLock { committed = true }
    }

    var didCommit: Bool {
        lock.withLock { committed }
    }
}

@Suite("DownloadManager account lifetime")
@MainActor
struct DownloadManagerLifetimeTests {
    @Test("background URLSession identifier is stable, account-separated, and opaque")
    func backgroundIdentifierIsOpaque() {
        let namespaceA = "account-v1-subject-a-sensitive"
        let namespaceB = "account-v1-subject-b-sensitive"
        let firstA = SegmentDownloadSession.sessionIdentifier(accountNamespace: namespaceA)
        let secondA = SegmentDownloadSession.sessionIdentifier(accountNamespace: namespaceA)
        let identifierB = SegmentDownloadSession.sessionIdentifier(accountNamespace: namespaceB)

        #expect(firstA == secondA)
        #expect(firstA != identifierB)
        #expect(!firstA.contains(namespaceA))
        #expect(!identifierB.contains(namespaceB))
        #expect(!firstA.contains("subject-a"))
        #expect(firstA.hasPrefix("com.chapterflow.ios.audio-segment-dl.v1."))
    }

    @Test("segment invalidation awaits delegate invalidation and releases retained session")
    func segmentInvalidationAwaitsDelegateAndReleasesSession() async throws {
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.isSuspended = true
        defer { delegateQueue.isSuspended = false }

        let segmentSession = SegmentDownloadSession(
            accountNamespace: "account-v1-invalidation-lifetime",
            configurationFactory: { _ in .ephemeral },
            delegateQueue: delegateQueue
        )
        try segmentSession.activateSessionForTesting()

        var snapshot = segmentSession.invalidationSnapshotForTesting
        #expect(snapshot.hasRetainedSession)
        #expect(snapshot.didBecomeInvalidCount == 0)

        let completionProbe = InvalidationCompletionProbe()
        let invalidationTask = Task {
            await segmentSession.invalidate()
            await completionProbe.markComplete()
        }

        let registeredWaiter = await waitForInvalidationWaiter(in: segmentSession)
        #expect(registeredWaiter)
        #expect(!(await completionProbe.didComplete))
        snapshot = segmentSession.invalidationSnapshotForTesting
        #expect(snapshot.hasRetainedSession)
        #expect(snapshot.didBecomeInvalidCount == 0)
        #expect(snapshot.waiterCount == 1)

        delegateQueue.isSuspended = false
        await invalidationTask.value

        snapshot = segmentSession.invalidationSnapshotForTesting
        #expect(snapshot.isInvalidated)
        #expect(!snapshot.hasRetainedSession)
        #expect(snapshot.didBecomeInvalidCount == 1)
        #expect(snapshot.waiterCount == 0)

        await segmentSession.invalidate()
        #expect(segmentSession.invalidationSnapshotForTesting.didBecomeInvalidCount == 1)
    }

    @Test("cancelAll cancels and awaits tracked tasks without invalidating the manager")
    func cancelAllAwaitsTrackedWork() async throws {
        let controlled = ControlledDownloadOperation()
        var started = controlled.started.stream.makeAsyncIterator()
        let segmentProbe = SegmentDownloaderProbe()
        let manager = try await makeManager(
            namespace: "account-v1-cancel-all",
            segmentDownloader: segmentProbe,
            operation: controlled
        )

        let firstStream = await manager.downloadBook(bookId: "book-1", userId: "account-a")
        _ = firstStream
        _ = await started.next()
        await manager.cancelAll()

        var snapshot = await manager.lifecycleSnapshotForTesting
        #expect(snapshot.state == .active)
        #expect(snapshot.activeTaskCount == 0)
        #expect(await segmentProbe.cancelAllCount == 1)

        let secondStream = await manager.downloadBook(bookId: "book-2", userId: "account-a")
        _ = secondStream
        _ = await started.next()
        snapshot = await manager.lifecycleSnapshotForTesting
        #expect(snapshot.activeTaskCount == 1)

        await manager.invalidate()
        #expect(await segmentProbe.invalidateCount == 1)
    }

    @Test("pause is reversible and final invalidation rejects all new work")
    func pauseResumeAndInvalidate() async throws {
        let controlled = ControlledDownloadOperation()
        var started = controlled.started.stream.makeAsyncIterator()
        let segmentProbe = SegmentDownloaderProbe()
        let manager = try await makeManager(
            namespace: "account-v1-pause-resume",
            segmentDownloader: segmentProbe,
            operation: controlled
        )

        let initialStream = await manager.downloadBook(bookId: "book-a", userId: "account-a")
        _ = initialStream
        _ = await started.next()
        await manager.pause()

        var snapshot = await manager.lifecycleSnapshotForTesting
        #expect(snapshot.state == .paused)
        #expect(snapshot.activeTaskCount == 0)
        #expect(await segmentProbe.cancelAllCount == 1)
        await expectRejected(await manager.downloadBook(bookId: "paused", userId: "account-a"))

        await manager.resume()
        let resumedStream = await manager.downloadBook(bookId: "book-b", userId: "account-a")
        _ = resumedStream
        _ = await started.next()
        snapshot = await manager.lifecycleSnapshotForTesting
        #expect(snapshot.state == .active)
        #expect(snapshot.activeTaskCount == 1)

        await manager.invalidate()
        await manager.invalidate()
        snapshot = await manager.lifecycleSnapshotForTesting
        #expect(snapshot.state == .invalidated)
        #expect(snapshot.activeTaskCount == 0)
        #expect(await segmentProbe.invalidateCount == 1)
        await expectRejected(await manager.downloadBook(bookId: "stopped", userId: "account-a"))
    }

    @Test("pause after segment lookup prevents a delayed destructive delete commit")
    func pauseBlocksDelayedDeleteCommit() async throws {
        let controlled = ControlledDownloadOperation()
        let gate = DeletePreparationGate()
        let commitProbe = DeleteCommitProbe()
        let permit = SessionWorkPermit()
        let manager = try await makeManager(
            namespace: "account-v1-delayed-delete",
            segmentDownloader: SegmentDownloaderProbe(),
            operation: controlled,
            workPermit: permit,
            beforeDeleteCommit: { await gate.block() },
            deleteCommitObserver: { commitProbe.markCommitted() }
        )

        let deletion = Task {
            try await manager.deleteBookDownload(bookId: "book-a", userId: "account-a")
        }
        await gate.waitUntilStarted()
        await manager.pause()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            try await deletion.value
        }
        #expect(commitProbe.didCommit == false)
        #expect(await manager.lifecycleSnapshotForTesting.state == .paused)
    }

    private func makeManager(
        namespace: String,
        segmentDownloader: any SegmentDownloading,
        operation: ControlledDownloadOperation,
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        beforeDeleteCommit: (@Sendable () async -> Void)? = nil,
        deleteCommitObserver: (@Sendable () -> Void)? = nil
    ) async throws -> DownloadManager {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "DownloadManagerLifetimeTests-\(UUID().uuidString)")
        let resources = try await InMemoryAccountPersistenceLoader(root: root)
            .load(storageNamespace: namespace)
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let preferences = AppPreferences(defaults: defaults, keyPrefix: "\(namespace).")
        return DownloadManager(
            resources: resources,
            apiClient: MockAPIClient(),
            preferences: preferences,
            segmentSession: segmentDownloader,
            downloadOperation: { _, _, _ in
                try await operation.run()
            },
            beforeDeleteCommit: beforeDeleteCommit,
            deleteCommitObserver: deleteCommitObserver,
            workPermit: workPermit
        )
    }

    private func expectRejected(_ stream: AsyncStream<DownloadProgress>) async {
        var iterator = stream.makeAsyncIterator()
        guard let event = await iterator.next() else {
            Issue.record("Expected an explicit inactive-session download failure")
            return
        }
        guard case .failed(let message) = event.phase else {
            Issue.record("Expected a failed progress event for inactive manager")
            return
        }
        #expect(message == DownloadError.inactive.localizedDescription)
    }

    private func waitForInvalidationWaiter(
        in session: SegmentDownloadSession
    ) async -> Bool {
        for _ in 0..<1_000 {
            if session.invalidationSnapshotForTesting.waiterCount == 1 {
                return true
            }
            await Task.yield()
        }
        return false
    }
}
