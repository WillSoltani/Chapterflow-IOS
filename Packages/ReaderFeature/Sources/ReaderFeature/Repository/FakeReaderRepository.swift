#if DEBUG
import Foundation
import Models
import Persistence

// MARK: - Fake (in-memory)

/// An in-memory `ReaderRepository` for Previews and unit tests.
///
/// Initialise with no arguments for a successful load using the built-in
/// EMH chapter fixture, or pass a custom `Result` to simulate any state.
public final class FakeReaderRepository: ReaderRepository, @unchecked Sendable {

    // MARK: - Configuration

    /// Chapter to return from `getChapter`. Override to inject errors.
    public var chapterResponse: Result<ChapterResponse, Error>

    /// Book state to return from `getBookState`. Override to inject specific states.
    public var bookStateResponse: Result<BookStateResponse, Error>

    /// The sessionId returned by `startReadingSession` (nil simulates server failure).
    public var startSessionId: String? = "fake-session-id"

    /// Recorded calls to `patchBookCursor` for assertion in unit tests.
    public private(set) var patchCursorCalls: [(bookId: String, chapterId: String)] = []

    /// Recorded calls to `startReadingSession`.
    public private(set) var startSessionCalls: [(bookId: String, chapterId: String)] = []

    /// Recorded calls to `postReadingHeartbeat`.
    public private(set) var heartbeatCalls: [HeartbeatCall] = []

    /// Recorded calls to `endReadingSession`.
    public private(set) var endSessionCalls: [SessionEventCall] = []

    /// Number of times `getBookState` has been called — used in tests to poll
    /// for book-state task completion without a fixed sleep.
    public private(set) var getBookStateCalls: Int = 0

    public struct HeartbeatCall: Sendable {
        public let bookId: String
        public let chapterId: String
        public let sessionId: String?
    }

    public struct SessionEventCall: Sendable {
        public let bookId: String
        public let chapterId: String
        public let sessionId: String?
    }

    /// In-memory position storage keyed by `"\(bookId).\(chapterNumber)"`.
    private var positions: [String: Int] = [:]

    // MARK: - Init

    /// Creates a fake repository that returns the built-in EMH chapter fixture.
    public init() {
        self.chapterResponse = .success(Self.makePreviewResponse())
        self.bookStateResponse = .success(Self.makeDefaultBookState())
    }

    /// Creates a fake repository with a custom response.
    public init(chapterResponse: Result<ChapterResponse, Error>) {
        self.chapterResponse = chapterResponse
        self.bookStateResponse = .success(Self.makeDefaultBookState())
    }

    // MARK: - ReaderRepository

    public func getChapter(bookId: String, n: Int, mode: String?) async throws -> ChapterResponse {
        switch chapterResponse {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    public func patchBookCursor(bookId: String, chapterId: String) async throws {
        patchCursorCalls.append((bookId: bookId, chapterId: chapterId))
    }

    public func startReadingSession(bookId: String, chapterId: String) async -> String? {
        startSessionCalls.append((bookId: bookId, chapterId: chapterId))
        return startSessionId
    }

    public func postReadingHeartbeat(bookId: String, chapterId: String, sessionId: String?) async {
        heartbeatCalls.append(HeartbeatCall(bookId: bookId, chapterId: chapterId, sessionId: sessionId))
    }

    public func endReadingSession(bookId: String, chapterId: String, sessionId: String?) async {
        endSessionCalls.append(SessionEventCall(bookId: bookId, chapterId: chapterId, sessionId: sessionId))
    }

    public func getBookState(bookId: String) async throws -> BookStateResponse {
        getBookStateCalls += 1
        switch bookStateResponse {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    public func saveScrollPosition(bookId: String, chapterNumber: Int, blockIndex: Int) {
        positions["\(bookId).\(chapterNumber)"] = blockIndex
    }

    public func loadScrollPosition(bookId: String, chapterNumber: Int) -> Int? {
        positions["\(bookId).\(chapterNumber)"]
    }

    // MARK: - Preview fixtures

    private static func makePreviewResponse() -> ChapterResponse {
        let json = """
        {
            "chapter": {
                "chapterId": "ch-ah-1",
                "number": 1,
                "title": "The Surprising Power of Atomic Habits",
                "readingTimeMinutes": 12,
                "activeVariant": "medium",
                "availableVariants": ["easy", "medium", "hard"],
                "content": {
                    "chapterBreakdown": {
                        "gentle": "Small habits compound into remarkable results over time.",
                        "direct": "1% better every day = 37x better in a year.",
                        "competitive": "Your competitors are sleeping. Compound your gains daily."
                    },
                    "keyTakeaways": [
                        {
                            "point": {
                                "gentle": "Tiny improvements each day create extraordinary long-term results.",
                                "direct": "Small consistent action beats big sporadic effort.",
                                "competitive": "Compound your edge daily."
                            },
                            "moreDetails": null
                        }
                    ]
                },
                "contentVariants": {
                    "easy": {
                        "chapterBreakdown": {
                            "gentle": "Small habits are the key.",
                            "direct": "1% better daily. Simple.",
                            "competitive": "Tiny daily wins add up."
                        }
                    },
                    "medium": {
                        "chapterBreakdown": {
                            "gentle": "Small habits compound into remarkable results over time.",
                            "direct": "1% better every day = 37x better in a year.",
                            "competitive": "Your competitors are sleeping."
                        },
                        "keyTakeaways": [
                            {
                                "point": {
                                    "gentle": "Tiny improvements each day create extraordinary results.",
                                    "direct": "Small consistent action beats big sporadic effort.",
                                    "competitive": "Compound your edge daily."
                                },
                                "moreDetails": null
                            }
                        ]
                    },
                    "hard": {
                        "chapterBreakdown": {
                            "gentle": "The mathematics of marginal gains reveals a counterintuitive truth.",
                            "direct": "Marginal gains compound exponentially.",
                            "competitive": "Elite performers understand that the gap is the relentless accumulation of marginal gains."
                        }
                    }
                },
                "examples": []
            },
            "progress": {
                "currentChapterNumber": 1,
                "unlockedThroughChapterNumber": 1,
                "completedChapters": [],
                "bestScoreByChapter": {},
                "preferredVariant": null,
                "progressRev": 1
            }
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: Data(json.utf8))
    }

    private static func makeDefaultBookState() -> BookStateResponse {
        BookStateResponse(
            state: BookUserBookState(
                currentChapterId: "ch-ah-1",
                completedChapterIds: [],
                unlockedChapterIds: ["ch-ah-1"],
                chapterScores: [:],
                chapterCompletedAt: [:],
                lastReadChapterId: nil,
                lastOpenedAt: nil
            ),
            applicationStates: [:]
        )
    }
}
#endif
