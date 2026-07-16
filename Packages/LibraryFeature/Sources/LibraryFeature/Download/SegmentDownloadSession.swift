import CryptoKit
import Foundation
import os

protocol SegmentDownloading: Sendable {
    var sessionIdentifier: String { get }
    func download(from url: URL, to destination: URL) async throws
    func cancelAll() async
    func invalidate() async
}

/// A `URLSessionDownloadDelegate`-based session bridge that converts completion
/// callbacks into Swift async continuations. Audio segment files are moved to
/// their final location inside the delegate method so the temporary file cannot
/// disappear before it is persisted.
///
/// Mutable continuation state is protected by `OSAllocatedUnfairLock`; continuations
/// are removed under that lock before resumption, so every operation completes once.
final class SegmentDownloadSession: NSObject, URLSessionDownloadDelegate, SegmentDownloading {
    typealias SegmentContinuation = CheckedContinuation<Void, any Error>
    typealias InvalidationContinuation = CheckedContinuation<Void, Never>

    private enum InvalidationDisposition {
        case beginInvalidation
        case awaitExistingInvalidation
        case alreadyInvalidated
    }

    private struct PendingTask {
        let operationID: UUID
        let task: URLSessionDownloadTask
        let continuation: SegmentContinuation
        let destURL: URL
    }

    private struct State {
        var pending: [Int: PendingTask] = [:]
        var taskIdentifierByOperation: [UUID: Int] = [:]
        var cancelledBeforeRegistration: Set<UUID> = []
        var session: URLSession?
        var isInvalidated = false
        var didRequestSessionInvalidation = false
        var didBecomeInvalidCount = 0
        var invalidationWaiters: [InvalidationContinuation] = []
    }

    let sessionIdentifier: String
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let configurationFactory: @Sendable (String) -> URLSessionConfiguration
    private let delegateQueue: OperationQueue?

    init(accountNamespace: String) {
        sessionIdentifier = Self.sessionIdentifier(accountNamespace: accountNamespace)
        configurationFactory = Self.backgroundConfiguration(identifier:)
        delegateQueue = nil
        super.init()
    }

    init(
        accountNamespace: String,
        configurationFactory: @escaping @Sendable (String) -> URLSessionConfiguration,
        delegateQueue: OperationQueue? = nil
    ) {
        sessionIdentifier = Self.sessionIdentifier(accountNamespace: accountNamespace)
        self.configurationFactory = configurationFactory
        self.delegateQueue = delegateQueue
        super.init()
    }

    static func sessionIdentifier(accountNamespace: String) -> String {
        let digest = SHA256.hash(data: Data(accountNamespace.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return "com.chapterflow.ios.audio-segment-dl.v1.\(digest)"
    }

    private static func backgroundConfiguration(identifier: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.networkServiceType = .responsiveAV
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        return configuration
    }

    private func sessionForWork() throws -> URLSession {
        try state.withLock { state in
            guard !state.isInvalidated else { throw CancellationError() }
            if let session = state.session { return session }
            let configuration = configurationFactory(sessionIdentifier)
            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: delegateQueue
            )
            state.session = session
            return session
        }
    }

    func download(from url: URL, to destURL: URL) async throws {
        let operationID = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: SegmentContinuation) in
                let session: URLSession
                do {
                    session = try sessionForWork()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let task = session.downloadTask(with: url)
                let shouldReject = state.withLock { state in
                    let wasCancelled = state.cancelledBeforeRegistration.remove(operationID) != nil
                    let shouldReject = state.isInvalidated || wasCancelled
                    if !shouldReject {
                        state.pending[task.taskIdentifier] = PendingTask(
                            operationID: operationID,
                            task: task,
                            continuation: continuation,
                            destURL: destURL
                        )
                        state.taskIdentifierByOperation[operationID] = task.taskIdentifier
                    }
                    return shouldReject
                }

                if shouldReject {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                } else {
                    task.resume()
                }
            }
        } onCancel: { [weak self] in
            self?.cancel(operationID: operationID)
        }
    }

    func cancelAll() async {
        let entries = drainPending(markInvalidated: false)
        cancelAndResume(entries)
        guard let session = state.withLock({ $0.session }) else { return }
        let sessionTasks = await session.allTasks
        sessionTasks.forEach { $0.cancel() }
    }

    func invalidate() async {
        let entries = drainPending(markInvalidated: true)
        cancelAndResume(entries)
        guard let session = state.withLock({ $0.session }) else { return }

        await withCheckedContinuation { continuation in
            let disposition = state.withLock { state -> InvalidationDisposition in
                if state.didBecomeInvalidCount > 0 {
                    return .alreadyInvalidated
                }
                state.invalidationWaiters.append(continuation)
                guard !state.didRequestSessionInvalidation else {
                    return .awaitExistingInvalidation
                }
                state.didRequestSessionInvalidation = true
                return .beginInvalidation
            }

            switch disposition {
            case .beginInvalidation:
                session.invalidateAndCancel()
            case .alreadyInvalidated:
                continuation.resume()
            case .awaitExistingInvalidation:
                break
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let entry = removePending(taskIdentifier: downloadTask.taskIdentifier)
        guard let entry else { return }
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: entry.destURL.path) {
                try fileManager.removeItem(at: entry.destURL)
            }
            try fileManager.moveItem(at: location, to: entry.destURL)
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
        let entry = removePending(taskIdentifier: task.taskIdentifier)
        entry?.continuation.resume(throwing: error)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        didBecomeInvalidWithError error: (any Error)?
    ) {
        let waiters = state.withLock { state -> [InvalidationContinuation] in
            state.isInvalidated = true
            state.didBecomeInvalidCount += 1
            if state.session === session {
                state.session = nil
            }
            let waiters = state.invalidationWaiters
            state.invalidationWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    private func cancel(operationID: UUID) {
        let entry = state.withLock { state -> PendingTask? in
            guard let taskIdentifier = state.taskIdentifierByOperation.removeValue(forKey: operationID) else {
                state.cancelledBeforeRegistration.insert(operationID)
                return nil
            }
            return state.pending.removeValue(forKey: taskIdentifier)
        }
        guard let entry else { return }
        entry.task.cancel()
        entry.continuation.resume(throwing: CancellationError())
    }

    private func removePending(taskIdentifier: Int) -> PendingTask? {
        state.withLock { state in
            let entry = state.pending.removeValue(forKey: taskIdentifier)
            if let entry {
                state.taskIdentifierByOperation.removeValue(forKey: entry.operationID)
                state.cancelledBeforeRegistration.remove(entry.operationID)
            }
            return entry
        }
    }

    private func drainPending(markInvalidated: Bool) -> [PendingTask] {
        state.withLock { state in
            if markInvalidated { state.isInvalidated = true }
            let entries = Array(state.pending.values)
            state.pending.removeAll()
            state.taskIdentifierByOperation.removeAll()
            // Do not clear cancellation markers: cancellation may race registration.
            // The registering operation removes its own marker deterministically.
            return entries
        }
    }

    private func cancelAndResume(_ entries: [PendingTask]) {
        for entry in entries {
            entry.task.cancel()
            entry.continuation.resume(throwing: CancellationError())
        }
    }

    struct InvalidationSnapshot: Sendable, Equatable {
        let isInvalidated: Bool
        let hasRetainedSession: Bool
        let didBecomeInvalidCount: Int
        let waiterCount: Int
    }

    var invalidationSnapshotForTesting: InvalidationSnapshot {
        state.withLock { state in
            InvalidationSnapshot(
                isInvalidated: state.isInvalidated,
                hasRetainedSession: state.session != nil,
                didBecomeInvalidCount: state.didBecomeInvalidCount,
                waiterCount: state.invalidationWaiters.count
            )
        }
    }

    func activateSessionForTesting() throws {
        _ = try sessionForWork()
    }
}
