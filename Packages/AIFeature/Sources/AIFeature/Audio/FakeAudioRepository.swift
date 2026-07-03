import Foundation
import Models

/// In-memory ``AudioRepository`` for SwiftUI `#Preview`s and unit tests.
///
/// Configure ``planToReturn`` for the happy path, ``errorToThrow`` to simulate
/// failures. Use ``fetchCallCount`` and ``planFetchHistory`` to assert call patterns.
public actor FakeAudioRepository: AudioRepository {

    // MARK: - Configuration

    /// The plan returned by ``fetchPlan(bookId:chapterNumber:)``.
    public var planToReturn: AudioNarrationPlan
    /// When non-nil, `fetchPlan` throws this error instead.
    public var errorToThrow: Error?
    /// Simulated download delay (seconds).
    public var downloadDelay: Double

    // MARK: - Observation

    public private(set) var fetchCallCount: Int = 0
    public private(set) var planFetchHistory: [(bookId: String, chapterNumber: Int)] = []
    public private(set) var downloadCallCount: Int = 0
    public private(set) var sessionEventCount: Int = 0

    // MARK: - Init

    public init(
        plan: AudioNarrationPlan = .makeFake(),
        errorToThrow: Error? = nil,
        downloadDelay: Double = 0
    ) {
        self.planToReturn = plan
        self.errorToThrow = errorToThrow
        self.downloadDelay = downloadDelay
    }

    // MARK: - AudioRepository

    public func fetchPlan(bookId: String, chapterNumber: Int) async throws -> AudioNarrationPlan {
        fetchCallCount += 1
        planFetchHistory.append((bookId, chapterNumber))
        if let err = errorToThrow { throw err }
        if downloadDelay > 0 {
            try await Task.sleep(for: .seconds(downloadDelay))
        }
        return planToReturn
    }

    public func downloadSegment(
        remoteURL: URL,
        segmentId: String,
        to directory: URL
    ) async throws -> URL {
        downloadCallCount += 1
        // Return a fake local URL — tests don't need real files.
        return directory.appending(path: "\(segmentId).mp3")
    }

    public nonisolated func localURL(for segmentId: String, in directory: URL) -> URL? {
        // By default report nothing is cached (allows download path testing).
        return nil
    }

    public func postAudioSessionEvent(
        event: String,
        bookId: String,
        chapterNumber: Int,
        sessionId: String?,
        listeningSeconds: Double?
    ) async throws {
        sessionEventCount += 1
    }
}

// MARK: - AudioNarrationPlan fake factory

public extension AudioNarrationPlan {
    /// A minimal synthetic plan suitable for previews and tests.
    static func makeFake(
        bookId: String = "b-atomic-habits",
        chapterNumber: Int = 1,
        chapterTitle: String = "The Habit Loop",
        bookTitle: String = "Atomic Habits",
        segmentDurations: [Double] = [10, 120, 185, 45]
    ) -> AudioNarrationPlan {
        let base = URL(string: "https://audio.example.com/")!
        let kinds: [AudioSegmentKind] = [.greeting, .body, .body, .takeaway]
        let segments: [AudioSegment] = zip(
            zip(kinds, segmentDurations).enumerated(),
            ["greeting-1", "body-1", "body-2", "takeaway-1"].prefix(segmentDurations.count)
        ).map { pair, segId in
            let (_, (kind, dur)) = pair
            return AudioSegment(
                segmentId: segId,
                kind: kind,
                url: base.appending(path: "\(segId).mp3"),
                durationSeconds: dur
            )
        }
        return AudioNarrationPlan(
            bookId: bookId,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            bookTitle: bookTitle,
            coverEmoji: "⚛️",
            coverColor: "#3B82F6",
            segments: segments
        )
    }
}
