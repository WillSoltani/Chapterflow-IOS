import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Helpers

private final class Box<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class StubCommitmentsClient: APIClientProtocol, Sendable {
    typealias Handler = @Sendable (Endpoint) async throws -> Data
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}

// MARK: - Fixtures

extension Commitment {
    static let testActive = Commitment(
        id: "test-001",
        bookId: "book-a",
        chapterId: "ch-1",
        ifStatement: "I wake up",
        thenStatement: "I will read for 10 minutes",
        followUpDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
        status: .active,
        outcome: nil,
        reflection: nil,
        createdAt: Date()
    )

    static let testDone = Commitment(
        id: "test-002",
        bookId: "book-b",
        chapterId: "ch-2",
        ifStatement: "I feel stressed",
        thenStatement: "I will take three deep breaths",
        followUpDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date(),
        status: .done,
        outcome: .helped,
        reflection: "Very helpful habit.",
        createdAt: Calendar.current.date(byAdding: .day, value: -12, to: Date()) ?? Date()
    )
}

// MARK: - Tests

@Suite("CommitmentRepository")
struct CommitmentRepositoryTests {

    @Test("fetchCommitments returns the server list")
    func fetchCommitmentsReturnsServerList() async throws {
        let client = StubCommitmentsClient { endpoint in
            #expect(endpoint.path == "/book/me/commitments")
            #expect(endpoint.method == .get)
            return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: [.testActive, .testDone]))
        }
        let repo = CommitmentRepository(apiClient: client)
        let result = try await repo.fetchCommitments()
        #expect(result.count == 2)
        #expect(result[0].id == "test-001")
    }

    @Test("fetchCommitments returns cached value without hitting network again")
    func fetchCommitmentsUsesCache() async throws {
        let callCount = Box(0)
        let client = StubCommitmentsClient { _ in
            callCount.value += 1
            return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: [.testActive]))
        }
        let repo = CommitmentRepository(apiClient: client)
        _ = try await repo.fetchCommitments()
        _ = try await repo.fetchCommitments()
        #expect(callCount.value == 1)
    }

    @Test("fetchCommitments forceRefresh bypasses cache")
    func fetchCommitmentsForceRefresh() async throws {
        let callCount = Box(0)
        let client = StubCommitmentsClient { _ in
            callCount.value += 1
            return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: [.testActive]))
        }
        let repo = CommitmentRepository(apiClient: client)
        _ = try await repo.fetchCommitments()
        _ = try await repo.fetchCommitments(forceRefresh: true)
        #expect(callCount.value == 2)
    }

    @Test("fetchCommitments offline falls back to in-memory cache")
    func fetchCommitmentsOfflineFallback() async throws {
        let shouldFail = Box(false)
        let client = StubCommitmentsClient { _ in
            if shouldFail.value { throw AppError.offline }
            return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: [.testActive]))
        }
        let repo = CommitmentRepository(apiClient: client)
        _ = try await repo.fetchCommitments()
        shouldFail.value = true
        let result = try await repo.fetchCommitments(forceRefresh: true)
        #expect(result.count == 1)
    }

    @Test("fetchCommitments offline throws when no cache")
    func fetchCommitmentsOfflineNoCache() async throws {
        let client = StubCommitmentsClient { _ in throw AppError.offline }
        let repo = CommitmentRepository(apiClient: client)
        do {
            _ = try await repo.fetchCommitments()
            Issue.record("Expected AppError.offline")
        } catch AppError.offline {
            // Expected
        }
    }

    @Test("createCommitment calls POST and returns new commitment")
    func createCommitmentCallsPost() async throws {
        let client = StubCommitmentsClient { endpoint in
            if endpoint.method == .get {
                return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: []))
            }
            #expect(endpoint.method == .post)
            #expect(endpoint.path == "/book/me/commitments")
            return try JSONCoding.encoder.encode(CommitmentResponse(commitment: .testActive))
        }
        let repo = CommitmentRepository(apiClient: client)
        let result = try await repo.createCommitment(
            bookId: "book-a",
            chapterId: "ch-1",
            ifStatement: "I wake up",
            thenStatement: "I will read",
            followUpDays: 3
        )
        #expect(result.id == "test-001")
        #expect(result.status == .active)
    }

    @Test("createCommitment offline creates a local placeholder and queues outbox")
    func createCommitmentOfflineQueues() async throws {
        let client = StubCommitmentsClient { endpoint in
            if endpoint.method == .get {
                return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: []))
            }
            throw AppError.offline
        }
        let repo = CommitmentRepository(apiClient: client)
        let result = try await repo.createCommitment(
            bookId: "book-a",
            chapterId: "ch-1",
            ifStatement: "I wake up",
            thenStatement: "I will read",
            followUpDays: 7
        )
        #expect(result.id.hasPrefix("local-"))
        #expect(result.status == .active)
        #expect(result.ifStatement == "I wake up")
    }

    @Test("submitReflection calls PATCH and returns updated commitment")
    func submitReflectionCallsPatch() async throws {
        let updatedCommitment = Commitment(
            id: "test-001",
            bookId: "book-a",
            chapterId: "ch-1",
            ifStatement: "I wake up",
            thenStatement: "I will read for 10 minutes",
            followUpDate: Date(),
            status: .done,
            outcome: .helped,
            reflection: "Really worked well!",
            createdAt: Date()
        )
        let client = StubCommitmentsClient { endpoint in
            if endpoint.method == .get && endpoint.path == "/book/me/commitments" {
                return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: [.testActive]))
            }
            #expect(endpoint.method == .patch)
            #expect(endpoint.path == "/book/me/commitments/test-001")
            return try JSONCoding.encoder.encode(CommitmentResponse(commitment: updatedCommitment))
        }
        let repo = CommitmentRepository(apiClient: client)
        _ = try await repo.fetchCommitments()
        let result = try await repo.submitReflection(
            commitmentId: "test-001",
            reflection: "Really worked well!",
            outcome: .helped
        )
        #expect(result.status == .done)
        #expect(result.outcome == .helped)
        #expect(result.reflection == "Really worked well!")
    }

    @Test("submitReflection offline optimistically updates memory")
    func submitReflectionOfflineOptimistic() async throws {
        let shouldFail = Box(false)
        let client = StubCommitmentsClient { endpoint in
            if shouldFail.value && endpoint.method == .patch { throw AppError.offline }
            if endpoint.method == .get {
                return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: [.testActive]))
            }
            return try JSONCoding.encoder.encode(CommitmentResponse(commitment: .testActive))
        }
        let repo = CommitmentRepository(apiClient: client)
        _ = try await repo.fetchCommitments()
        shouldFail.value = true
        let result = try await repo.submitReflection(
            commitmentId: "test-001",
            reflection: "Offline reflection",
            outcome: .partly
        )
        #expect(result.status == .done)
        #expect(result.outcome == .partly)
    }

    @Test("activeCommitments returns only active commitments")
    func activeCommitmentsFilter() async throws {
        let client = StubCommitmentsClient { _ in
            return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: [.testActive, .testDone]))
        }
        let repo = CommitmentRepository(apiClient: client)
        _ = try await repo.fetchCommitments()
        let active = await repo.activeCommitments
        #expect(active.count == 1)
        #expect(active[0].id == "test-001")
    }

    @Test("invalidate clears in-memory state")
    func invalidateClearsMemory() async throws {
        let client = StubCommitmentsClient { _ in
            return try JSONCoding.encoder.encode(CommitmentsResponse(commitments: [.testActive]))
        }
        let repo = CommitmentRepository(apiClient: client)
        _ = try await repo.fetchCommitments()
        #expect(await repo.commitments != nil)
        await repo.invalidate()
        #expect(await repo.commitments == nil)
    }
}

// MARK: - Evolution tests

@Suite("Commitment tolerant decoding")
struct CommitmentEvolutionTests {

    @Test("CommitmentOutcome decodes unknown raw value to .unknown")
    func outcomeUnknown() throws {
        let json = "\"future_outcome_type\"".data(using: .utf8)!
        let outcome = try JSONCoding.decoder.decode(CommitmentOutcome.self, from: json)
        if case .unknown(let raw) = outcome {
            #expect(raw == "future_outcome_type")
        } else {
            Issue.record("Expected .unknown, got \(outcome)")
        }
    }

    @Test("CommitmentStatus decodes unknown raw value to .unknown")
    func statusUnknown() throws {
        let json = "\"archived\"".data(using: .utf8)!
        let status = try JSONCoding.decoder.decode(CommitmentStatus.self, from: json)
        if case .unknown(let raw) = status {
            #expect(raw == "archived")
        } else {
            Issue.record("Expected .unknown, got \(status)")
        }
    }

    @Test("CommitmentsResponse decodes lossily, surviving one corrupt element")
    func commitmentsLossyDecode() throws {
        let json = """
        {
            "commitments": [
                {
                    "id": "cmt-valid",
                    "bookId": "book-a",
                    "chapterId": "ch-1",
                    "ifStatement": "I wake up",
                    "thenStatement": "I will read",
                    "followUpDate": "2026-07-10T09:00:00Z",
                    "status": "active",
                    "createdAt": "2026-07-03T08:00:00Z"
                },
                null,
                {
                    "id": "cmt-valid-2",
                    "bookId": "book-b",
                    "chapterId": "ch-2",
                    "ifStatement": "I sit down",
                    "thenStatement": "I will write",
                    "followUpDate": "2026-07-17T09:00:00Z",
                    "status": "done",
                    "outcome": "helped",
                    "reflection": "Worked!",
                    "createdAt": "2026-07-01T08:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(CommitmentsResponse.self, from: json)
        #expect(resp.commitments.count == 2)
        #expect(resp.commitments[0].id == "cmt-valid")
        #expect(resp.commitments[1].id == "cmt-valid-2")
    }

    @Test("Commitment decodes with unknown future top-level fields")
    func commitmentToleratesUnknownFields() throws {
        let json = """
        {
            "id": "cmt-future",
            "bookId": "book-z",
            "chapterId": "ch-z",
            "ifStatement": "I trigger",
            "thenStatement": "I act",
            "followUpDate": "2026-08-01T09:00:00Z",
            "status": "active",
            "createdAt": "2026-07-03T08:00:00Z",
            "newFutureField": "ignored",
            "anotherFutureField": 42
        }
        """.data(using: .utf8)!
        let commitment = try JSONCoding.decoder.decode(Commitment.self, from: json)
        #expect(commitment.id == "cmt-future")
        #expect(commitment.status == .active)
        #expect(commitment.outcome == nil)
    }

    @Test("Commitment decodes with unknown outcome to .unknown, does not crash")
    func commitmentUnknownOutcomeDoesNotCrash() throws {
        let json = """
        {
            "id": "cmt-future-outcome",
            "bookId": "book-z",
            "chapterId": "ch-z",
            "ifStatement": "I trigger",
            "thenStatement": "I act",
            "followUpDate": "2026-08-01T09:00:00Z",
            "status": "done",
            "outcome": "super_helped",
            "reflection": "text",
            "createdAt": "2026-07-03T08:00:00Z"
        }
        """.data(using: .utf8)!
        let commitment = try JSONCoding.decoder.decode(Commitment.self, from: json)
        if case .unknown(let raw) = commitment.outcome {
            #expect(raw == "super_helped")
        } else {
            Issue.record("Expected .unknown outcome, got \(String(describing: commitment.outcome))")
        }
    }
}
