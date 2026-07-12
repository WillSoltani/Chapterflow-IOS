import Foundation

/// Coalesces concurrent StoreKit delivery paths for one transaction.
///
/// A purchase result, `Transaction.updates`, and entitlement reconciliation can
/// all surface the same transaction while the backend request is suspended. The
/// first caller performs verification; duplicates await that exact result so the
/// backend request, transaction finish, and entitlement event occur only once.
actor StoreKitTransactionProcessingCoordinator {
    private typealias ProcessingResult = StoreKitTransactionProcessingResult
    private typealias WaiterContinuation = AsyncStream<Outcome>.Continuation

    struct Key: Hashable, Sendable {
        let transactionID: UInt64
        let accountToken: UUID
        let accountSessionGeneration: UInt64
    }

    struct Outcome: Sendable {
        let result: Result<StoreKitTransactionProcessingResult, any Error>
        let participationID: UUID
    }

    private struct InFlightProcessing {
        let leaderID: UUID
        var waiters: [UUID: WaiterContinuation] = [:]
    }

    private struct CompletedProcessing {
        let result: Result<StoreKitTransactionProcessingResult, any Error>
        var remainingParticipantIDs: Set<UUID>
        var eventClaimed = false
    }

    private var inFlightProcessing: [Key: InFlightProcessing] = [:]
    private var completedProcessing: [Key: CompletedProcessing] = [:]

    func perform(
        key: Key,
        operation: @Sendable @escaping () async throws -> StoreKitTransactionProcessingResult
    ) async throws -> Outcome {
        if var completed = completedProcessing[key] {
            let participationID = UUID()
            completed.remainingParticipantIDs.insert(participationID)
            completedProcessing[key] = completed
            return Outcome(
                result: completed.result,
                participationID: participationID
            )
        }
        if inFlightProcessing[key] != nil {
            return try await waitForLeader(key: key)
        }

        let leaderID = UUID()
        inFlightProcessing[key] = InFlightProcessing(leaderID: leaderID)

        let result: Result<ProcessingResult, any Error>
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }
        return completeProcessing(
            key: key,
            leaderID: leaderID,
            result: result
        )
    }

    /// Atomically finalizes one participant and grants the cohort's sole event
    /// publication permit when that participant requests it.
    func completeParticipation(
        key: Key,
        participationID: UUID,
        requestsEvent: Bool
    ) -> Bool {
        guard var completed = completedProcessing[key],
              completed.remainingParticipantIDs.remove(participationID) != nil else {
            return false
        }

        let publishesEvent = requestsEvent && !completed.eventClaimed
        if publishesEvent {
            completed.eventClaimed = true
        }
        if completed.remainingParticipantIDs.isEmpty {
            completedProcessing.removeValue(forKey: key)
        } else {
            completedProcessing[key] = completed
        }
        return publishesEvent
    }

    func participantCount(for key: Key) -> Int {
        if let processing = inFlightProcessing[key] {
            return processing.waiters.count + 1
        }
        return completedProcessing[key]?.remainingParticipantIDs.count ?? 0
    }

    private func completeProcessing(
        key: Key,
        leaderID: UUID,
        result: Result<ProcessingResult, any Error>
    ) -> Outcome {
        guard let processing = inFlightProcessing.removeValue(forKey: key) else {
            return Outcome(result: result, participationID: leaderID)
        }

        let participantIDs = Set(processing.waiters.keys).union([processing.leaderID])
        completedProcessing[key] = CompletedProcessing(
            result: result,
            remainingParticipantIDs: participantIDs
        )
        for (waiterID, continuation) in processing.waiters {
            continuation.yield(
                Outcome(result: result, participationID: waiterID)
            )
            continuation.finish()
        }
        return Outcome(result: result, participationID: processing.leaderID)
    }

    private func waitForLeader(key: Key) async throws -> Outcome {
        try Task.checkCancellation()
        let waiterID = UUID()
        let (stream, continuation) = AsyncStream<Outcome>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        guard var processing = inFlightProcessing[key] else {
            throw CancellationError()
        }
        processing.waiters[waiterID] = continuation
        inFlightProcessing[key] = processing
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task {
                await self?.cancelWaiter(
                    key: key,
                    waiterID: waiterID
                )
            }
        }

        var iterator = stream.makeAsyncIterator()
        guard let outcome = await iterator.next() else {
            removeWaiter(key: key, waiterID: waiterID)
            throw CancellationError()
        }
        if Task.isCancelled {
            _ = completeParticipation(
                key: key,
                participationID: outcome.participationID,
                requestsEvent: false
            )
            throw CancellationError()
        }
        return outcome
    }

    private func cancelWaiter(key: Key, waiterID: UUID) {
        if let waiter = inFlightProcessing[key]?.waiters.removeValue(forKey: waiterID) {
            waiter.finish()
            return
        }
        _ = completeParticipation(
            key: key,
            participationID: waiterID,
            requestsEvent: false
        )
    }

    private func removeWaiter(key: Key, waiterID: UUID) {
        inFlightProcessing[key]?.waiters.removeValue(forKey: waiterID)
    }
}
