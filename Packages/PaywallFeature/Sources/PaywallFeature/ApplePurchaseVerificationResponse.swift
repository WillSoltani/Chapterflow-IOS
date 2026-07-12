import Foundation

/// The deployed success body for `POST /book/me/billing/apple/verify`.
///
/// This endpoint intentionally returns only the authoritative billing fields,
/// not the larger `GET /book/me/entitlements` response. Unknown JSON keys are
/// ignored by synthesized `Decodable`, preserving forward compatibility.
public struct ApplePurchaseVerificationResponse: Decodable, Sendable {
    public let ok: Bool
    public let processed: Bool?
    public let transactionState: String?
    public let entitlement: EntitlementSnapshot

    enum ProcessedTransactionState: Equatable, Sendable {
        case active
        case expired
        case revoked
        case unknown(String)
    }

    var processedTransactionState: ProcessedTransactionState? {
        guard let transactionState else { return nil }
        switch transactionState {
        case "active":
            return .active
        case "expired":
            return .expired
        case "revoked":
            return .revoked
        default:
            return .unknown(transactionState)
        }
    }

    /// `true` only for the additive backend contract that explicitly confirms
    /// the signed transaction was safely handled. Older responses without the
    /// acknowledgement remain unfinished so a newer client never guesses.
    public var confirmsAuthoritativelyProcessed: Bool {
        guard ok, processed == true else { return false }
        switch processedTransactionState {
        case .active, .expired, .revoked:
            return true
        case .unknown, nil:
            return false
        }
    }

    /// Whether the backend's authoritative entitlement remains active after it
    /// processed the Apple transaction. The source can intentionally remain a
    /// higher-priority promo/admin/license grant; Apple is not assumed locally.
    public var authoritativeProIsActive: Bool {
        confirmsAuthoritativelyProcessed
            && transactionState == "active"
            && entitlement.plan == "PRO"
            && entitlement.proStatus == "active"
    }

    public struct EntitlementSnapshot: Decodable, Equatable, Sendable {
        public let plan: String
        public let proStatus: String?
        public let proSource: String?
        public let currentPeriodEnd: String?
        public let cancelAtPeriodEnd: Bool?
    }
}

/// A syntactically valid 2xx body that does not carry the additive processed
/// acknowledgement is a contract failure and must never finish a transaction.
struct InvalidAppleVerificationAcknowledgement: Error, Sendable {}
