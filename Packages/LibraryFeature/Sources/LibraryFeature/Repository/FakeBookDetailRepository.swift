import Models
import CoreKit

/// In-memory ``BookDetailRepository`` for unit tests and SwiftUI previews.
///
/// Seed it with fixture data and configure `stateError` to simulate a book that
/// hasn't been started yet (`.notFound`) or any other failure.
public actor FakeBookDetailRepository: BookDetailRepository {

    private let manifestStub: BookManifest
    private let stateStub: BookStateResponse?
    private let entitlementStub: EntitlementResponse
    private let forcedError: AppError?
    /// Error thrown specifically by `getBookState` — set to `.notFound` to simulate
    /// a book the user hasn't started.
    private let stateError: AppError?

    public init(
        manifest: BookManifest,
        state: BookStateResponse? = nil,
        stateError: AppError? = nil,
        entitlement: EntitlementResponse,
        error: AppError? = nil
    ) {
        self.manifestStub = manifest
        self.stateStub = state
        self.stateError = stateError
        self.entitlementStub = entitlement
        self.forcedError = error
    }

    public func getBook(id: String) async throws -> BookManifest {
        if let e = forcedError { throw e }
        return manifestStub
    }

    public func getBookState(id: String) async throws -> BookStateResponse {
        if let e = forcedError { throw e }
        if let e = stateError { throw e }
        guard let state = stateStub else { throw AppError.notFound }
        return state
    }

    public func startBook(id: String) async throws -> BookStateResponse {
        if let e = forcedError { throw e }
        // After starting, return the current stub (simulates the server creating state).
        guard let state = stateStub else {
            // Return an initial empty state
            return BookStateResponse(
                state: BookUserBookState(
                    currentChapterId: manifestStub.chapters.first?.chapterId,
                    completedChapterIds: [],
                    unlockedChapterIds: manifestStub.chapters.prefix(1).map(\.chapterId),
                    chapterScores: [:],
                    chapterCompletedAt: [:],
                    lastReadChapterId: nil,
                    lastOpenedAt: nil
                ),
                applicationStates: nil
            )
        }
        return state
    }

    public func getEntitlements() async throws -> EntitlementResponse {
        if let e = forcedError { throw e }
        return entitlementStub
    }
}
