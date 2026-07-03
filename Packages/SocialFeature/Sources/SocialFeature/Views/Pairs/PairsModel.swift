import Foundation
import Observation
import CoreKit

/// Observable model driving ``PairsView`` and supporting pair operations.
@Observable
@MainActor
public final class PairsModel {

    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - State

    public private(set) var phase: Phase = .idle
    public private(set) var pairs: [ReadingPair] = []

    /// Set after a successful nudge; drives a transient confirmation toast.
    public private(set) var lastNudgedPartnerId: String?

    /// Set while a nudge is in-flight (keyed by partner ID).
    public private(set) var nudgingPartnerId: String?

    /// Set while an unpair is in-flight (keyed by partner ID).
    public private(set) var unpairingPartnerId: String?

    /// Set while accepting an invite.
    public var isAccepting: Bool = false

    /// Error message surfaced by accept / nudge / unpair operations.
    public var operationError: String?

    // MARK: - Dependencies

    private let repository: any SocialRepository

    // MARK: - Init

    public init(repository: any SocialRepository) {
        self.repository = repository
    }

    // MARK: - Load

    public func load() async {
        phase = .loading
        do {
            pairs = try await repository.getPairs()
            phase = .loaded
        } catch let appError as AppError {
            phase = .error(appError.errorDescription ?? appError.code)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Accept invite

    /// Returns the accepted pair on success so the caller can navigate to it.
    @discardableResult
    public func acceptInvite(code: String) async throws -> ReadingPair {
        isAccepting = true
        operationError = nil
        defer { isAccepting = false }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.invalidInput("Please enter an invite code.")
        }
        let pair = try await repository.acceptInvite(code: trimmed)
        // Refresh the full list after accepting.
        if let idx = pairs.firstIndex(where: { $0.partnerId == pair.partnerId }) {
            pairs[idx] = pair
        } else {
            pairs.append(pair)
        }
        return pair
    }

    // MARK: - Nudge

    public func nudge(partnerId: String) async {
        guard nudgingPartnerId == nil else { return }
        nudgingPartnerId = partnerId
        operationError = nil
        defer { nudgingPartnerId = nil }
        do {
            try await repository.nudgePartner(partnerId: partnerId)
            lastNudgedPartnerId = partnerId
        } catch let appError as AppError {
            operationError = appError.errorDescription ?? appError.code
        } catch {
            operationError = error.localizedDescription
        }
    }

    // MARK: - Unpair

    public func unpair(partnerId: String) async {
        guard unpairingPartnerId == nil else { return }
        unpairingPartnerId = partnerId
        operationError = nil
        defer { unpairingPartnerId = nil }
        do {
            try await repository.deletePair(partnerId: partnerId)
            pairs.removeAll { $0.partnerId == partnerId }
        } catch let appError as AppError {
            operationError = appError.errorDescription ?? appError.code
        } catch {
            operationError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    var activePairs: [ReadingPair] { pairs.filter { $0.status == .active } }
    var pendingPairs: [ReadingPair] { pairs.filter { $0.status == .pending } }
    var expiredPairs: [ReadingPair] { pairs.filter { $0.status == .expired } }
}
