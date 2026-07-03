import Foundation
import Observation
import CoreKit
import Models

// MARK: - CommitmentsModel

@Observable
@MainActor
public final class CommitmentsModel {

    // MARK: Load state

    public enum LoadState {
        case idle
        case loading
        case loaded([Commitment])
        case error(AppError)
    }

    // MARK: State

    public internal(set) var loadState: LoadState = .idle
    public private(set) var isCreating: Bool = false
    public private(set) var isSubmittingReflection: Bool = false

    // MARK: Dependencies

    private let repository: CommitmentRepository

    // MARK: Init

    public init(repository: CommitmentRepository) {
        self.repository = repository
    }

    // MARK: - Load

    public func load() {
        guard case .idle = loadState else { return }
        Task { await fetchCommitments() }
    }

    public func refresh() async {
        await fetchCommitments(forceRefresh: true)
    }

    // MARK: - Create

    /// Returns the newly created commitment, or throws on failure.
    public func createCommitment(
        bookId: String,
        chapterId: String,
        ifStatement: String,
        thenStatement: String,
        followUpDays: Int
    ) async throws -> Commitment {
        isCreating = true
        defer { isCreating = false }
        let commitment = try await repository.createCommitment(
            bookId: bookId,
            chapterId: chapterId,
            ifStatement: ifStatement,
            thenStatement: thenStatement,
            followUpDays: followUpDays
        )
        // Refresh the list so the new item appears immediately.
        await fetchCommitments(forceRefresh: true)
        return commitment
    }

    // MARK: - Reflect

    /// Submits a reflection for a commitment's follow-up. Returns the updated commitment.
    public func submitReflection(
        commitmentId: String,
        reflection: String,
        outcome: CommitmentOutcome
    ) async throws -> Commitment {
        isSubmittingReflection = true
        defer { isSubmittingReflection = false }
        let updated = try await repository.submitReflection(
            commitmentId: commitmentId,
            reflection: reflection,
            outcome: outcome
        )
        await fetchCommitments(forceRefresh: true)
        return updated
    }

    // MARK: - Accessors

    public var activeCommitments: [Commitment] {
        guard case .loaded(let all) = loadState else { return [] }
        return all.filter { $0.status == .active }
    }

    public var doneCommitments: [Commitment] {
        guard case .loaded(let all) = loadState else { return [] }
        return all.filter { $0.status == .done }
    }

    /// Commitments whose follow-up date has passed and are still active.
    public var overdueCommitments: [Commitment] {
        let now = Date()
        return activeCommitments.filter { $0.followUpDate <= now }
    }

    // MARK: - Private

    private func fetchCommitments(forceRefresh: Bool = false) async {
        if !forceRefresh {
            loadState = .loading
        }
        do {
            let list = try await repository.fetchCommitments(forceRefresh: forceRefresh)
            loadState = .loaded(list)
        } catch let error as AppError {
            if case .loaded = loadState { return }
            loadState = .error(error)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }
}
