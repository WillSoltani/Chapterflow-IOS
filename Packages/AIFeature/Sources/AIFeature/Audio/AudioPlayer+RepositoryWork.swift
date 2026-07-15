import Foundation

extension AudioPlayer {
    /// Downloads all segments of the current plan to `directory` for offline playback.
    /// Re-fetches a fresh plan first to refresh the presigned URLs.
    public func downloadChapter(
        bookId: String,
        chapterNumber: Int,
        to directory: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard acceptsRemoteWork() else { throw CancellationError() }
        let generation = remoteGeneration
        let freshPlan = try await remoteRepository.fetchPlan(
            bookId: bookId,
            chapterNumber: chapterNumber
        )
        try Task.checkCancellation()
        guard acceptsRemoteWork(generation) else { throw CancellationError() }
        let total = Double(freshPlan.segments.count)
        for (index, segment) in freshPlan.segments.enumerated() {
            try Task.checkCancellation()
            guard acceptsRemoteWork(generation) else { throw CancellationError() }
            _ = try await remoteRepository.downloadSegment(
                remoteURL: segment.url,
                segmentId: segment.segmentId,
                to: directory
            )
            guard acceptsRemoteWork(generation) else { throw CancellationError() }
            progress?(Double(index + 1) / total)
        }
    }

    public func postListeningSession(
        event: String,
        sessionId: String?,
        listeningSeconds: Double?
    ) async {
        guard acceptsRemoteWork(), let context = remoteListeningContext else { return }
        try? await remoteRepository.postAudioSessionEvent(
            event: event,
            bookId: context.bookId,
            chapterNumber: context.chapterNumber,
            sessionId: sessionId,
            listeningSeconds: listeningSeconds
        )
    }

    /// Heuristic: is this error likely a presigned URL expiry (HTTP 403)?
    func isLikelyExpiry(_ error: NSError?) -> Bool {
        guard let error else { return false }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSURLErrorDomain {
            return true
        }
        return false
    }
}
