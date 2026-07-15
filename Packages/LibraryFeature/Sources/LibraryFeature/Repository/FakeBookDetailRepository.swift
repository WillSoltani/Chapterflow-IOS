import Models
import CoreKit

/// In-memory ``BookDetailRepository`` for unit tests and SwiftUI previews.
///
/// Seed it with fixture data and configure operation-specific errors to exercise
/// partial Book Detail failures without affecting the public manifest.
public actor FakeBookDetailRepository: BookDetailRepository {

    private let manifestStub: BookManifest
    private let stateStub: BookStateGetResponse?
    private let startStateStub: BookStateResponse?
    private let entitlementStub: EntitlementResponse
    private let forcedError: AppError?
    private let stateError: AppError?
    private let entitlementError: AppError?
    private let startError: AppError?

    public init(
        manifest: BookManifest,
        state: BookStateGetResponse? = nil,
        stateError: AppError? = nil,
        startState: BookStateResponse? = nil,
        startError: AppError? = nil,
        entitlement: EntitlementResponse,
        entitlementError: AppError? = nil,
        error: AppError? = nil
    ) {
        self.manifestStub = manifest
        self.stateStub = state
        self.stateError = stateError
        self.startStateStub = startState
        self.startError = startError
        self.entitlementStub = entitlement
        self.entitlementError = entitlementError
        self.forcedError = error
    }

    public func getBook(id: String) async throws -> BookManifest {
        if let e = forcedError { throw e }
        return manifestStub
    }

    public func getBookState(id: String) async throws -> BookStateGetResponse {
        if let e = forcedError { throw e }
        if let e = stateError { throw e }
        guard let state = stateStub else { throw AppError.notFound }
        return state
    }

    public func startBook(id: String) async throws -> BookStateResponse {
        if let e = forcedError { throw e }
        if let e = startError { throw e }
        if let startStateStub { return startStateStub }
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

    public func getEntitlements() async throws -> EntitlementResponse {
        if let e = forcedError { throw e }
        if let e = entitlementError { throw e }
        return entitlementStub
    }
}
