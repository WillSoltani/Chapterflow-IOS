import CoreKit
import Models
import Testing
@testable import LibraryFeature

@MainActor
@Suite("BookDetailModel — authoritative private state")
struct BookDetailReliabilityTests {
    @Test("missing and unknown status remain compatibility-unknown", arguments: [
        Optional<BookStateStatus>.none,
        BookStateStatus.unknown("paused"),
    ])
    func compatibilityStatus(status: BookStateStatus?) async {
        let repo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: response(status: status),
            entitlement: BookDetailModelTests.proEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)

        await model.fetch()

        #expect(model.manifest != nil)
        #expect(model.primaryAction == .disabled)
        #expect(model.bookState == nil)
        if case .compatibilityUnknown = model.privateState { } else {
            Issue.record("Expected compatibility-unknown")
        }
    }

    @Test("private failures preserve metadata and never become not-started")
    func privateFailuresFailClosed() async {
        let failures: [AppError] = [
            .offline,
            .unauthenticated,
            .notFound,
            .server(code: "private", message: "private backend message", requestId: nil),
            .decoding(TestDecodeFailure()),
        ]

        for failure in failures {
            let repo = FakeBookDetailRepository(
                manifest: BookDetailModelTests.manifest,
                stateError: failure,
                entitlement: BookDetailModelTests.proEntitlement()
            )
            let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)

            await model.fetch()

            #expect(model.manifest?.bookId == "b-atomic-habits")
            #expect(model.primaryAction == .disabled)
            #expect(model.bookState == nil)
            if case .unavailable = model.privateState { } else {
                Issue.record("Expected unavailable for \(failure.code)")
            }
        }
    }

    @Test("not-started waits for entitlement, while started can continue without it")
    func entitlementFailureIsExplicit() async {
        let notStartedRepo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: BookDetailModelTests.notStartedState,
            entitlement: BookDetailModelTests.proEntitlement(),
            entitlementError: .offline
        )
        let notStarted = BookDetailModel(bookId: "b-atomic-habits", repository: notStartedRepo)
        await notStarted.fetch()
        #expect(notStarted.primaryAction == .disabled)
        if case .unavailable = notStarted.entitlementState { } else {
            Issue.record("Expected unavailable entitlement")
        }

        let startedRepo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: BookDetailModelTests.inProgressState,
            entitlement: BookDetailModelTests.proEntitlement(),
            entitlementError: .offline
        )
        let started = BookDetailModel(bookId: "b-atomic-habits", repository: startedRepo)
        await started.fetch()
        #expect(started.primaryAction == .continueReading)
    }

    @Test("private retry calls only the state endpoint")
    func focusedPrivateRetry() async {
        let retriedState = BookDetailModelTests.inProgressState
        let repo = ControlledBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            entitlement: BookDetailModelTests.proEntitlement(),
            startState: retriedState
        ) { call in
            if call == 1 { throw AppError.offline }
            return retriedState
        }
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)

        await model.fetch()
        if case .unavailable = model.privateState { } else {
            Issue.record("Expected initial private failure")
        }
        await model.retryPrivateState()

        #expect(model.primaryAction == .continueReading)
        let counts = await repo.counts()
        #expect(counts.book == 1)
        #expect(counts.state == 2)
        #expect(counts.entitlement == 1)
    }

    @Test("cancellation cannot publish not-started")
    func cancellationFailsClosed() async {
        let repo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: BookDetailModelTests.notStartedState,
            entitlement: BookDetailModelTests.proEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)

        let task = Task { await model.fetch() }
        task.cancel()
        await task.value

        #expect(model.primaryAction == .disabled)
        if case .notStarted = model.privateState {
            Issue.record("Cancellation must not publish not-started")
        }
    }

    @Test("a stale completion cannot overwrite a newer authoritative result")
    func staleCompletionIsIgnored() async {
        let firstCallStarted = TestSignal()
        let firstResponse = TestGate<BookStateGetResponse>()
        let staleStartedState = BookDetailModelTests.inProgressState
        let freshNotStartedState = BookDetailModelTests.notStartedState
        let repo = ControlledBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            entitlement: BookDetailModelTests.proEntitlement(),
            startState: staleStartedState
        ) { call in
            if call == 1 {
                await firstCallStarted.signal()
                return await firstResponse.wait()
            }
            return freshNotStartedState
        }
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)

        let firstFetch = Task { await model.fetch() }
        await firstCallStarted.wait()
        await model.fetch()
        #expect(model.primaryAction == .startReading)

        await firstResponse.open(staleStartedState)
        await firstFetch.value

        #expect(model.primaryAction == .startReading)
        if case .notStarted = model.privateState { } else {
            Issue.record("Stale started result overwrote the newer not-started result")
        }
    }

    @Test("disabled compatibility state invokes no private action callback")
    func disabledActionIsInert() async {
        let repo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: response(status: nil),
            entitlement: BookDetailModelTests.proEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        var opened = false
        var paywall = false
        model.onOpenReader = { _, _, _ in opened = true }
        model.onShowPaywall = { paywall = true }

        await model.fetch()
        await model.performPrimaryAction()

        #expect(!opened)
        #expect(!paywall)
    }

    @Test("start failure exposes only curated error data")
    func startFailureIsCurated() async throws {
        let secret = "private-token https://example.test?account=private"
        let repo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: BookDetailModelTests.notStartedState,
            startError: .server(code: "PRIVATE", message: secret, requestId: nil),
            entitlement: BookDetailModelTests.proEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)

        await model.fetch()
        await model.performPrimaryAction()

        let error = try #require(model.startError)
        let rendered = String(reflecting: error)
        #expect(!rendered.contains("private-token"))
        #expect(!rendered.contains("example.test"))
        #expect(error.category == .serviceUnavailable)
    }

    private func response(status: BookStateStatus?) -> BookStateGetResponse {
        BookStateGetResponse(
            stateStatus: status,
            state: BookDetailModelTests.inProgressState.state,
            applicationStates: BookDetailModelTests.inProgressState.applicationStates
        )
    }
}

private actor ControlledBookDetailRepository: BookDetailRepository {
    struct Counts: Sendable {
        let book: Int
        let state: Int
        let entitlement: Int
    }

    private let stateHandler: @Sendable (Int) async throws -> BookStateGetResponse
    private let manifest: BookManifest
    private let entitlement: EntitlementResponse
    private let startState: BookStateGetResponse
    private var bookCalls = 0
    private var stateCalls = 0
    private var entitlementCalls = 0

    init(
        manifest: BookManifest,
        entitlement: EntitlementResponse,
        startState: BookStateGetResponse,
        stateHandler: @escaping @Sendable (Int) async throws -> BookStateGetResponse
    ) {
        self.manifest = manifest
        self.entitlement = entitlement
        self.startState = startState
        self.stateHandler = stateHandler
    }

    func getBook(id: String) async throws -> BookManifest {
        bookCalls += 1
        return manifest
    }

    func getBookState(id: String) async throws -> BookStateGetResponse {
        stateCalls += 1
        return try await stateHandler(stateCalls)
    }

    func startBook(id: String) async throws -> BookStateResponse {
        BookStateResponse(
            state: startState.state,
            applicationStates: startState.applicationStates
        )
    }

    func getEntitlements() async throws -> EntitlementResponse {
        entitlementCalls += 1
        return entitlement
    }

    func counts() -> Counts {
        Counts(book: bookCalls, state: stateCalls, entitlement: entitlementCalls)
    }
}

private actor TestGate<Value: Sendable> {
    private var buffered: Value?
    private var continuation: CheckedContinuation<Value, Never>?

    func wait() async -> Value {
        if let buffered {
            self.buffered = nil
            return buffered
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open(_ value: Value) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
        } else {
            buffered = value
        }
    }
}

private actor TestSignal {
    private var signaled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func signal() {
        signaled = true
        continuation?.resume()
        continuation = nil
    }
}

private struct TestDecodeFailure: Error {}
