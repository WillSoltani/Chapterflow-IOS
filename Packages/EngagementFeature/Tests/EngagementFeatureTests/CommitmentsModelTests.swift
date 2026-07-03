import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - CommitmentsModel tests

@Suite("CommitmentsModel")
@MainActor
struct CommitmentsModelTests {

    private func makeModel(commitments: [Commitment]) -> CommitmentsModel {
        let repo = CommitmentRepository(apiClient: StubAllCommitmentsClient(commitments: commitments))
        return CommitmentsModel(repository: repo)
    }

    @Test("activeCommitments filters to only active status")
    func activeCommitmentsFiltered() {
        let model = CommitmentsModel(repository: CommitmentRepository.previewEmpty)
        model.loadState = .loaded([.testActive, .testDone])
        #expect(model.activeCommitments.count == 1)
        #expect(model.activeCommitments[0].id == "test-001")
    }

    @Test("doneCommitments filters to only done status")
    func doneCommitmentsFiltered() {
        let model = CommitmentsModel(repository: CommitmentRepository.previewEmpty)
        model.loadState = .loaded([.testActive, .testDone])
        #expect(model.doneCommitments.count == 1)
        #expect(model.doneCommitments[0].id == "test-002")
    }

    @Test("overdueCommitments returns active commitments past follow-up date")
    func overdueCommitmentsDetected() {
        let overdue = Commitment(
            id: "overdue-1",
            bookId: "book-x",
            chapterId: "ch-x",
            ifStatement: "trigger",
            thenStatement: "action",
            followUpDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            status: .active,
            outcome: nil,
            reflection: nil,
            createdAt: Date()
        )
        let model = CommitmentsModel(repository: CommitmentRepository.previewEmpty)
        model.loadState = .loaded([overdue, .testActive])
        #expect(model.overdueCommitments.count == 1)
        #expect(model.overdueCommitments[0].id == "overdue-1")
    }

    @Test("overdueCommitments is empty when all active are in the future")
    func overdueCommitmentsEmptyWhenFuture() {
        let model = CommitmentsModel(repository: CommitmentRepository.previewEmpty)
        model.loadState = .loaded([.testActive])
        #expect(model.overdueCommitments.isEmpty)
    }

    @Test("load transitions from idle to loaded")
    func loadTransitions() async throws {
        let model = makeModel(commitments: [.testActive])
        model.load()
        // Give the task a moment to resolve
        try await Task.sleep(for: .milliseconds(100))
        guard case .loaded(let list) = model.loadState else {
            Issue.record("Expected .loaded state")
            return
        }
        #expect(list.count == 1)
    }

    @Test("load is idempotent — second call while loading is a no-op")
    func loadIsIdempotent() async throws {
        let model = makeModel(commitments: [.testActive])
        model.load()
        model.load() // Second call during loading should be ignored
        try await Task.sleep(for: .milliseconds(100))
        guard case .loaded(let list) = model.loadState else {
            Issue.record("Expected .loaded state")
            return
        }
        #expect(list.count == 1)
    }
}

// MARK: - Stub

private final class StubAllCommitmentsClient: APIClientProtocol, Sendable {
    private let commitments: [Commitment]
    init(commitments: [Commitment]) { self.commitments = commitments }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data: Data
        switch endpoint.method {
        case .get where endpoint.path == "/book/me/commitments":
            data = try JSONCoding.encoder.encode(CommitmentsResponse(commitments: commitments))
        case .post where endpoint.path == "/book/me/commitments":
            let created = commitments.first ?? .testActive
            data = try JSONCoding.encoder.encode(CommitmentResponse(commitment: created))
        case .patch:
            let updated = commitments.first ?? .testActive
            data = try JSONCoding.encoder.encode(CommitmentResponse(commitment: updated))
        default:
            throw AppError.notFound
        }
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}
