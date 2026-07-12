import Foundation
import StoreKit
import CoreKit
import Models
import Networking
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Subscription Detail State

/// Comprehensive subscription lifecycle state for the management screen.
///
/// Derived from both the backend `Entitlement` and the local StoreKit status.
/// For Apple subscriptions, StoreKit is authoritative for billing lifecycle
/// (grace period, billing retry, etc.). For non-Apple sources, the backend
/// entitlement is the only signal.
public enum SubscriptionDetailState: Sendable, Equatable {
    // MARK: Apple states
    /// Active Apple subscription that will auto-renew.
    case appleActive(productID: String, renewsAt: Date?)
    /// Active Apple subscription set to cancel at period end.
    case applyCancelling(productID: String, expiresAt: Date?)
    /// In grace period: payment failed but Pro access continues temporarily.
    case appleGracePeriod(productID: String, expiresAt: Date?)
    /// Grace period ended; Apple is retrying billing.
    case appleBillingRetry(productID: String)
    /// Apple subscription has expired and was not renewed.
    case appleExpired(productID: String)
    /// Apple subscription was refunded or revoked.
    case appleRevoked
    /// Purchase pending parental approval (Ask-to-Buy) or SCA.
    case applePending

    // MARK: Non-Apple states
    /// Active Stripe (web) subscription.
    case stripeActive(renewsAt: Date?, cancelsAtPeriodEnd: Bool)
    /// Stripe subscription is past-due; payment failed.
    case stripePastDue(renewsAt: Date?)
    /// Active license-key grant.
    case licenseActive(key: String?, expiresAt: Date?)
    /// Active gift-code grant.
    case giftActive(expiresAt: Date?)
    /// Admin grant or other non-standard Pro source.
    case adminOrOther(sourceName: String, expiresAt: Date?)

    // MARK: Free
    case free

    // MARK: - Derived helpers

    /// `true` when the state confers Pro access (including grace period).
    public var isPro: Bool {
        switch self {
        case .appleActive, .applyCancelling, .appleGracePeriod, .appleBillingRetry,
             .applePending, .stripeActive, .stripePastDue,
             .licenseActive, .giftActive, .adminOrOther:
            return true
        case .appleExpired, .appleRevoked, .free:
            return false
        }
    }

    /// `true` when a billing-attention banner should be prominently shown.
    public var requiresBillingAttention: Bool {
        switch self {
        case .appleGracePeriod, .appleBillingRetry, .stripePastDue: return true
        default: return false
        }
    }

    /// The source for display in the plan header.
    var proSourceKind: ProSourceKind {
        switch self {
        case .appleActive, .applyCancelling, .appleGracePeriod,
             .appleBillingRetry, .appleExpired, .appleRevoked, .applePending:
            return .apple
        case .stripeActive, .stripePastDue:
            return .stripe
        case .licenseActive:
            return .license
        case .giftActive:
            return .gift
        case .adminOrOther:
            return .admin
        case .free:
            return .apple // no source; irrelevant for free
        }
    }

    /// Offer-code redemption is limited to accounts that already have an
    /// Apple-backed server entitlement history. A free/pending account has no
    /// trustworthy transaction-to-account map for tokenless offer-code delivery.
    var permitsOfferCodeRedemption: Bool {
        switch self {
        case .appleActive, .applyCancelling, .appleGracePeriod,
             .appleBillingRetry, .appleExpired, .appleRevoked:
            return true
        case .applePending, .stripeActive, .stripePastDue, .licenseActive,
             .giftActive, .adminOrOther, .free:
            return false
        }
    }
}

// MARK: - Refund Request Outcome

public enum RefundRequestOutcome: Sendable, Equatable {
    case idle
    case success
    case userCancelled
    case failed(String)
}

// MARK: - SubscriptionManagementModel

/// Observable model driving `SubscriptionManagementView`.
///
/// Merges backend entitlement data with the local StoreKit subscription lifecycle
/// to produce a single `SubscriptionDetailState` the view can render without
/// conditional-nesting complexity.
///
/// Handles:
/// - Fetching fresh entitlement + StoreKit status on appear.
/// - Surfacing the correct CTA per source (Apple → `manageSubscriptionsSheet`;
///   Stripe/license/gift → web links or informational text).
/// - In-app refund requests via SwiftUI's `.refundRequestSheet(for:isPresented:)`.
/// - StoreKit price-increase consent messages via `Message.messages`.
@Observable
@MainActor
public final class SubscriptionManagementModel {

    // MARK: - Public state

    public private(set) var detailState: SubscriptionDetailState = .free
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var refundOutcome: RefundRequestOutcome = .idle

    /// Transaction ID for SwiftUI's `.refundRequestSheet(for:isPresented:)`.
    /// `nil` when no active Apple transaction exists.
    public private(set) var activeTransactionID: UInt64?

    /// Drives `.refundRequestSheet` presentation.
    public var showRefundSheet = false

    /// Drives `.manageSubscriptionsSheet` presentation.
    public var showManageSubscriptionsSheet = false

    /// Drives the system offer-code redemption sheet.
    /// Resulting transaction is handled by `StoreKitService.Transaction.updates`.
    public var showOfferCodeRedemption = false

    // MARK: - Dependencies

    private let storeKitService: any StoreKitServicing
    private let apiClient: any APIClientProtocol
    private let log = AppLog(category: .billing)

    private let messageListenerTaskHandle = TaskCancellationHandle()

    // MARK: - Init

    public init(
        storeKitService: any StoreKitServicing,
        apiClient: any APIClientProtocol
    ) {
        self.storeKitService = storeKitService
        self.apiClient = apiClient
    }

    nonisolated deinit {
        messageListenerTaskHandle.cancel()
    }

    // MARK: - Preview / test injection

    func inject(detailState: SubscriptionDetailState, transactionID: UInt64? = nil) {
        self.detailState = detailState
        self.activeTransactionID = transactionID
    }

    /// Resets the refund outcome back to `.idle`.
    /// Called from the view after the refund result alert is dismissed.
    public func resetRefundOutcome() {
        refundOutcome = .idle
    }

    // MARK: - Lifecycle

    public func onAppear() async {
        await refresh()
        startPriceConsentListener()
    }

    // MARK: - Refresh

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let entitlementFetch: EntitlementResponse = apiClient.send(Endpoints.getEntitlements())
            async let skStatusFetch: SubscriptionStatus = storeKitService.currentSubscriptionStatus()
            let (response, skStatus) = try await (entitlementFetch, skStatusFetch)
            try Task.checkCancellation()
            let refreshedState = Self.computeState(
                entitlement: response.entitlement,
                skStatus: skStatus
            )
            let refreshedTransactionID = await storeKitService.currentTransactionID()
            try Task.checkCancellation()
            detailState = refreshedState
            activeTransactionID = refreshedTransactionID
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            log.warning("Subscription management refresh failed: \(Self.safeErrorCode(for: error))")
            errorMessage = "Could not load subscription details. Pull to refresh."
        }
    }

    // MARK: - Actions

    /// Presents the system App Store manage-subscriptions sheet.
    public func manageAppleSubscription() {
        showManageSubscriptionsSheet = true
    }

    /// Triggers the system offer-code redemption sheet.
    ///
    /// The resulting transaction flows through `Transaction.updates` in
    /// `StoreKitService` and is posted to the backend automatically.
    public func redeemOfferCode() {
        guard detailState.permitsOfferCodeRedemption else {
            errorMessage = "Offer codes are available after an Apple subscription is linked to this account."
            return
        }
        showOfferCodeRedemption = true
    }

    /// Presents the in-app refund-request sheet.
    ///
    /// No-ops when no active Apple transaction ID is available (non-Apple sources
    /// are managed externally and don't support in-app refunds).
    public func requestRefund() {
        guard activeTransactionID != nil else { return }
        showRefundSheet = true
    }

    /// Called by the view after the refund sheet dismisses.
    public func handleRefundResult(_ result: Result<StoreKit.Transaction.RefundRequestStatus, StoreKit.Transaction.RefundRequestError>) {
        switch result {
        case .success(let status):
            switch status {
            case .success:
                refundOutcome = .success
            case .userCancelled:
                refundOutcome = .userCancelled
            @unknown default:
                refundOutcome = .userCancelled
            }
        case .failure(let error):
            refundOutcome = Self.safeRefundFailureOutcome(for: error)
            if refundOutcome != .userCancelled {
                log.warning("Refund request failed: \(Self.safeErrorCode(for: error))")
            }
        }
    }

    // MARK: - Price-Increase Consent Listener

    /// Listens for StoreKit price-increase-consent messages and presents the
    /// system UI. Runs for the lifetime of this model.
    private func startPriceConsentListener() {
        messageListenerTaskHandle.installIfEmpty(
            Task { [weak self] in
                #if canImport(UIKit)
                for await message in Message.messages {
                    guard message.reason == .priceIncreaseConsent else { continue }
                    guard let self else { return }
                    do {
                        guard let scene = UIApplication.shared.connectedScenes
                            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                        else { continue }
                        try await message.display(in: scene)
                    } catch {
                        guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                        self.log.warning(
                            "Price-consent display failed: \(Self.safeErrorCode(for: error))"
                        )
                    }
                }
                #endif
            }
        )
    }

    // MARK: - Safe error mapping

    nonisolated static func safeRefundFailureOutcome(for error: any Error) -> RefundRequestOutcome {
        guard !isCancellation(error) else { return .userCancelled }
        return .failed("We couldn't submit the refund request. Please try again.")
    }

    nonisolated static func safeErrorCode(for error: any Error) -> String {
        if isCancellation(error) { return "cancelled" }
        guard let appError = error as? AppError else {
            return "subscription_operation_failed"
        }
        switch appError {
        case .unauthenticated:
            return "unauthenticated"
        case .reauthRequired:
            return "reauth_required"
        case .verifierUnavailable:
            return "verifier_unavailable"
        case .rateLimited:
            return "rate_limited"
        case .forbidden:
            return "forbidden"
        case .offline:
            return "offline"
        case .invalidInput:
            return "invalid_input"
        case .notFound:
            return "not_found"
        case .server:
            return "server"
        case .decoding:
            return "decoding"
        }
    }

    nonisolated static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    // MARK: - State Computation

    /// Computes the single comprehensive `SubscriptionDetailState` from both
    /// backend entitlement and local StoreKit status.
    ///
    /// For Apple sources, StoreKit is authoritative for billing lifecycle granularity
    /// (grace period, billing retry). For all other sources, the backend entitlement
    /// is the sole signal.
    nonisolated static func computeState(
        entitlement: Entitlement,
        skStatus: SubscriptionStatus
    ) -> SubscriptionDetailState {
        guard entitlement.plan == .pro else { return .free }

        let source = ProSourceKind(rawSource: entitlement.proSource)
        let periodEnd = parseDate(entitlement.currentPeriodEnd)
        let cancelAtEnd = entitlement.cancelAtPeriodEnd ?? false

        switch source {
        case .apple:
            return computeAppleState(
                skStatus: skStatus,
                backendPeriodEnd: periodEnd,
                backendCancelAtEnd: cancelAtEnd
            )
        case .stripe:
            let isProStatusPastDue = entitlement.proStatus == "past_due"
            if isProStatusPastDue {
                return .stripePastDue(renewsAt: periodEnd)
            }
            return .stripeActive(renewsAt: periodEnd, cancelsAtPeriodEnd: cancelAtEnd)
        case .license:
            let licenseExpiry = parseDate(entitlement.licenseExpiresAt)
            return .licenseActive(key: entitlement.licenseKey, expiresAt: licenseExpiry)
        case .gift:
            return .giftActive(expiresAt: periodEnd)
        case .admin, .flowPoints, .unknown:
            return .adminOrOther(sourceName: source.displayName, expiresAt: periodEnd)
        case .other(let rawSource):
            return .adminOrOther(sourceName: rawSource, expiresAt: periodEnd)
        }
    }

    private nonisolated static func computeAppleState(
        skStatus: SubscriptionStatus,
        backendPeriodEnd: Date?,
        backendCancelAtEnd: Bool
    ) -> SubscriptionDetailState {
        switch skStatus {
        case .inGracePeriod(let pid, let exp):
            return .appleGracePeriod(productID: pid, expiresAt: exp)
        case .inBillingRetry(let pid):
            return .appleBillingRetry(productID: pid)
        case .revoked:
            return .appleRevoked
        case .expired(let pid):
            return .appleExpired(productID: pid)
        case .pending:
            return .applePending
        case .subscribed(let pid, let exp):
            if backendCancelAtEnd {
                return .applyCancelling(productID: pid, expiresAt: exp ?? backendPeriodEnd)
            }
            return .appleActive(productID: pid, renewsAt: exp ?? backendPeriodEnd)
        case .notSubscribed, .unknown:
            // Backend confirms Apple Pro but SK hasn't synced yet — trust backend.
            if backendCancelAtEnd {
                return .applyCancelling(productID: "", expiresAt: backendPeriodEnd)
            }
            return .appleActive(productID: "", renewsAt: backendPeriodEnd)
        }
    }

    nonisolated static func parseDate(_ string: String?) -> Date? {
        guard let str = string else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: str) { return d }
        return ISO8601DateFormatter().date(from: str)
    }
}
