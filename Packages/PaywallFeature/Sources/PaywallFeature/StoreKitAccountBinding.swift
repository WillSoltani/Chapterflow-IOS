import Foundation
import StoreKit
import Synchronization

/// Opaque StoreKit account binding derived from the authenticated Cognito subject.
///
/// Cognito subjects are UUIDs. Passing the same UUID to StoreKit as an
/// `appAccountToken` lets the backend prove that a signed transaction belongs to
/// the authenticated ChapterFlow account without exposing email or display-name
/// data to Apple.
struct StoreKitAccountBinding: Hashable, Sendable {
    let token: UUID
    let sessionGeneration: UInt64

    init?(authenticatedSubject: String) {
        let subject = authenticatedSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = UUID(uuidString: subject) else { return nil }
        self.token = token
        sessionGeneration = 0
    }

    fileprivate init(token: UUID, sessionGeneration: UInt64) {
        self.token = token
        self.sessionGeneration = sessionGeneration
    }

    var purchaseOption: Product.PurchaseOption {
        .appAccountToken(token)
    }
}

/// Synchronously clears account identity at the auth boundary while StoreKit
/// operations remain actor-isolated. `Mutex` makes the one small piece of
/// cross-actor session state race-free without introducing an async teardown gap.
final class StoreKitAccountContext: Sendable {
    private struct State: Sendable {
        var binding: StoreKitAccountBinding?
        var verifiedLegacyTransactionIDs: Set<UInt64> = []
        var generation: UInt64 = 0
    }

    private let state = Mutex(State())

    @discardableResult
    func activate(authenticatedSubject: String) -> Bool {
        let nextBinding = StoreKitAccountBinding(
            authenticatedSubject: authenticatedSubject
        )
        state.withLock { state in
            guard state.binding?.token != nextBinding?.token else { return }
            state.generation &+= 1
            state.binding = nextBinding.map {
                StoreKitAccountBinding(
                    token: $0.token,
                    sessionGeneration: state.generation
                )
            }
            state.verifiedLegacyTransactionIDs = []
        }
        return nextBinding != nil
    }

    func deactivate() {
        state.withLock { state in
            guard state.binding != nil || !state.verifiedLegacyTransactionIDs.isEmpty else {
                return
            }
            state.generation &+= 1
            state.binding = nil
            state.verifiedLegacyTransactionIDs = []
        }
    }

    func currentBinding() -> StoreKitAccountBinding? {
        state.withLock { $0.binding }
    }

    func authorizeLegacyTransaction(
        _ transactionID: UInt64,
        for binding: StoreKitAccountBinding
    ) {
        state.withLock { state in
            guard state.binding == binding else { return }
            state.verifiedLegacyTransactionIDs.insert(transactionID)
        }
    }

    func ownsTransaction(
        id transactionID: UInt64,
        appAccountToken: UUID?
    ) -> Bool {
        state.withLock { state in
            guard let binding = state.binding else { return false }
            if let appAccountToken {
                return appAccountToken == binding.token
            }
            return state.verifiedLegacyTransactionIDs.contains(transactionID)
        }
    }
}

/// The result of processing a locally verified StoreKit transaction.
///
/// Only ``activeProcessed(proSource:)`` may become a successful purchase in the
/// UI. Its source comes from the backend's authoritative entitlement; the
/// client never assumes Apple won precedence. Terminal transactions are safe
/// to finish after acknowledgement, but they never grant Pro locally.
enum StoreKitTransactionProcessingResult: Equatable, Sendable {
    case ignored
    case activeProcessed(proSource: String?)
    case terminal
}
