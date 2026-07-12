import Foundation
import CoreKit
import Models
import Networking
import Persistence
#if canImport(UIKit)
import UIKit
#endif

/// The single source of truth for subscription access throughout the app.
///
/// Merges two inputs:
/// - **Backend entitlement** (`GET /book/me/entitlements`) — authoritative once the
///   server has processed an Apple transaction.
/// - **Local StoreKit status** from ``StoreKitService`` — drives reconciliation
///   and billing-lifecycle UI but never grants access by itself.
///
/// **Cross-platform reconciliation (P4.7):** on every `refresh()`, an
/// ``EntitlementReconciler`` compares the backend state with the local StoreKit
/// subscription. When StoreKit shows an active Apple subscription the backend
/// hasn't processed yet (e.g. a renewal), it re-posts the JWS via
/// `POST /book/me/billing/apple/verify` and re-fetches the backend entitlement.
///
/// Never writes unlocks or completions client-side. Gating is always server-truth.
@Observable
@MainActor
public final class EntitlementService {

    // MARK: - Cache migration

    private static let legacyUnscopedCacheKey = "com.chapterflow.entitlement.v1"

    // MARK: - Public state

    /// `true` when the user holds an active Pro subscription.
    ///
    /// `true` only when the backend confirms Pro with `proStatus == "active"`.
    /// Local StoreKit state can request verification but cannot grant access.
    public private(set) var isPro: Bool = false

    /// `true` when the user can open a new book.
    ///
    /// `isPro || remainingFreeStarts > 0`
    public private(set) var canStartNewBook: Bool = false

    /// The raw `proSource` field from the backend entitlement.
    ///
    /// Common values: `"stripe"`, `"apple"`, `"license"`, `"gift_code"`, `"admin"`.
    /// `nil` when the user is on the free tier or the entitlement hasn't loaded yet.
    /// Use this to display source-specific messaging (e.g. "Pro via web" for Stripe).
    public private(set) var proSource: String?

    // MARK: - Private state

    private var backendEntitlement: Entitlement?
    private var storeKitStatus: SubscriptionStatus = .unknown
    private var accountScope: EntitlementAccountScope?
    private var accountGeneration: UInt64 = 0
    private var refreshFlightID: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var refreshRequestedDuringFlight = false
    private var needsCurrentEntitlementAuthorization = false
    private let reconciler = EntitlementReconciler()

    // MARK: - Dependencies

    private let storeKitService: any StoreKitServicing
    private let apiClient: any APIClientProtocol
    private let store: KeyValueStore
    private let storeKitConfig: StoreKitConfig
    private let log = AppLog(category: .billing)

    private let storeKitListenerTaskHandle = TaskCancellationHandle()
    private let foregroundListenerTaskHandle = TaskCancellationHandle()

    // MARK: - Init

    /// Creates an `EntitlementService`.
    ///
    /// The initializer starts fail-closed with no account-private state. Call
    /// ``activateAccount(_:)`` after authentication resolves; activation then
    /// synchronously warms only that account's cache. Call ``start()`` once at
    /// app startup to begin background listeners.
    ///
    /// - Parameters:
    ///   - storeKitService: The StoreKit 2 service.
    ///   - apiClient: The authenticated API client.
    ///   - storeKitConfig: The StoreKit product ID configuration.
    ///   - store: Key-value store for the offline entitlement cache.
    public init(
        storeKitService: any StoreKitServicing,
        apiClient: any APIClientProtocol,
        storeKitConfig: StoreKitConfig,
        store: KeyValueStore = KeyValueStore()
    ) {
        self.storeKitService = storeKitService
        self.apiClient = apiClient
        self.storeKitConfig = storeKitConfig
        self.store = store
        // The v1 key was global. Never migrate its account-private value into an
        // authenticated scope because ownership cannot be proven.
        store.removeValue(forKey: Self.legacyUnscopedCacheKey)
    }

    /// Convenience initializer for use when StoreKit config isn't needed.
    /// The reconciler will have no known product IDs and will skip Apple verification.
    public convenience init(
        storeKitService: any StoreKitServicing,
        apiClient: any APIClientProtocol,
        store: KeyValueStore = KeyValueStore()
    ) {
        self.init(
            storeKitService: storeKitService,
            apiClient: apiClient,
            storeKitConfig: StoreKitConfig(monthlyProductID: "", annualProductID: ""),
            store: store
        )
    }

    nonisolated deinit {
        storeKitListenerTaskHandle.cancel()
        foregroundListenerTaskHandle.cancel()
    }

    // MARK: - Plan detail accessors

    /// The end of the current billing period; `nil` when not on a Pro plan.
    ///
    /// Parses the server's ISO-8601 string (with or without fractional seconds).
    public var currentPeriodEnd: Date? {
        guard let str = backendEntitlement?.currentPeriodEnd else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: str) { return d }
        return ISO8601DateFormatter().date(from: str)
    }

    /// `true` when the Pro subscription is set to cancel at period end; `nil` when not on Pro.
    public var cancelAtPeriodEnd: Bool? { backendEntitlement?.cancelAtPeriodEnd }

    /// How many free book starts remain. Zero when the entitlement is not yet loaded.
    public var remainingFreeStarts: Int { backendEntitlement?.remainingFreeStarts ?? 0 }

    // MARK: - Gating queries

    /// `true` if the given book is accessible without consuming a free start.
    ///
    /// Returns `true` when Pro (any book is unlocked), or when the book appears
    /// in the server-issued `unlockedBookIds` list (e.g. purchased via Flow Points).
    public func isBookUnlocked(_ bookId: String) -> Bool {
        if isPro { return true }
        return backendEntitlement?.unlockedBookIds.contains(bookId) ?? false
    }

    /// The reason the book cannot be accessed, or `nil` when no lock applies.
    ///
    /// `nil` is returned when `isBookUnlocked(bookId)` is `true` OR when
    /// `canStartNewBook` is `true` (the user can still start it using a free slot).
    ///
    /// - Parameters:
    ///   - bookId: The book to evaluate.
    ///   - isLockedByQuiz: Pass `true` when the calling feature knows the book
    ///     requires a prerequisite quiz to be completed first.
    public func lockReason(for bookId: String, isLockedByQuiz: Bool = false) -> LockReason? {
        if isBookUnlocked(bookId) || canStartNewBook { return nil }
        if isLockedByQuiz { return .lockedBehindQuiz }
        let freeBookSlots = backendEntitlement?.freeBookSlots ?? 0
        return freeBookSlots > 0 ? .needsFreeSlotOrPro : .needsPro
    }

    // MARK: - Lifecycle

    /// Activates entitlement state for one authenticated account.
    ///
    /// Any prior account is torn down first. Cache warming is synchronous and
    /// limited to the opaque account scope; network refresh remains explicit.
    public func activateAccount(_ scope: EntitlementAccountScope) {
        guard accountScope != scope else { return }

        if let accountScope {
            store.removeValue(forKey: accountScope.cacheKey)
        }
        invalidateRefreshes()
        accountScope = scope
        backendEntitlement = store.value(Entitlement.self, forKey: scope.cacheKey)
        storeKitStatus = .unknown
        needsCurrentEntitlementAuthorization = true
        updateDerivedState()
    }

    /// Ends the current account scope and fails all entitlement gates closed.
    ///
    /// The active account cache is erased, in-flight refreshes are invalidated,
    /// and no late response can restore the signed-out account's state.
    public func deactivateAccount() {
        if let accountScope {
            store.removeValue(forKey: accountScope.cacheKey)
        }
        invalidateRefreshes()
        accountScope = nil
        backendEntitlement = nil
        storeKitStatus = .unknown
        needsCurrentEntitlementAuthorization = false
        updateDerivedState()
    }

    /// Starts background listeners and triggers an initial refresh.
    ///
    /// Call once at app startup (composition root). Idempotent — safe to call
    /// again after the app re-enters the foreground.
    public func start() {
        startStoreKitListener()
        startForegroundListener()
        Task { await refresh() }
    }

    // MARK: - Refresh

    /// Refreshes entitlement state from both the backend and StoreKit,
    /// then runs cross-platform reconciliation.
    ///
    /// On success, updates `isPro`, `canStartNewBook`, `proSource`, and the offline cache.
    /// On failure, keeps the last known state to avoid flickering.
    ///
    /// Reconciliation: if StoreKit shows an active Apple subscription the backend
    /// hasn't reflected (e.g. a renewal), this method re-verifies the transaction
    /// with the backend and re-fetches the entitlement.
    ///
    /// Public so callers (e.g., post-purchase flow) can trigger an explicit
    /// refresh without waiting for the next background cycle.
    public func refresh() async {
        guard let accountScope else { return }
        if let refreshTask {
            refreshRequestedDuringFlight = true
            let flightID = refreshFlightID
            await refreshTask.value
            await finishRefreshFlight(flightID)
            return
        }

        refreshFlightID &+= 1
        let flightID = refreshFlightID
        let generation = accountGeneration
        refreshRequestedDuringFlight = false
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performRefreshFlights(
                accountScope: accountScope,
                generation: generation
            )
        }
        refreshTask = task
        await task.value
        await finishRefreshFlight(flightID)
    }

    // MARK: - Private fetch

    private func performRefresh(
        accountScope: EntitlementAccountScope,
        generation: UInt64
    ) async {
        await replayUnfinishedTransactions(
            accountScope: accountScope,
            generation: generation
        )
        await authorizeCurrentEntitlementsIfNeeded(
            accountScope: accountScope,
            generation: generation
        )
        await fetchBackendEntitlement(accountScope: accountScope, generation: generation)
        await fetchStoreKitStatus(accountScope: accountScope, generation: generation)
        await reconcileAndVerifyIfNeeded(accountScope: accountScope, generation: generation)
    }

    private func replayUnfinishedTransactions(
        accountScope: EntitlementAccountScope,
        generation: UInt64
    ) async {
        guard isCurrent(accountScope: accountScope, generation: generation) else { return }
        do {
            try await storeKitService.verifyUnfinishedTransactions()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            log.warning("Unfinished StoreKit replay failed: \(Self.safeErrorCode(error))")
        }
    }

    /// Re-establishes ownership of tokenless legacy or offer-code transactions
    /// after process launch or account activation. Successful authorization is
    /// remembered for this account session; failures remain retryable.
    private func authorizeCurrentEntitlementsIfNeeded(
        accountScope: EntitlementAccountScope,
        generation: UInt64
    ) async {
        guard isCurrent(accountScope: accountScope, generation: generation),
              needsCurrentEntitlementAuthorization else { return }
        do {
            try await storeKitService.verifyCurrentEntitlements()
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            needsCurrentEntitlementAuthorization = false
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            log.warning("Current StoreKit account authorization failed: \(Self.safeErrorCode(error))")
        }
    }

    /// Runs refreshes serially. Any number of requests received during one
    /// flight collapse into exactly one trailing flight with a fresh backend
    /// read, so a response started before an entitlement event cannot win.
    private func performRefreshFlights(
        accountScope: EntitlementAccountScope,
        generation: UInt64
    ) async {
        while true {
            await performRefresh(accountScope: accountScope, generation: generation)
            guard isCurrent(accountScope: accountScope, generation: generation),
                  refreshRequestedDuringFlight else { return }
            refreshRequestedDuringFlight = false
        }
    }

    /// Clears the completed shared task. This also closes the narrow window
    /// where a new request can observe a completed task before its original
    /// caller resumes and schedules that request as a new trailing flight.
    private func finishRefreshFlight(_ flightID: UInt64) async {
        guard refreshFlightID == flightID, refreshTask != nil else { return }
        refreshTask = nil
        guard refreshRequestedDuringFlight else { return }
        refreshRequestedDuringFlight = false
        await refresh()
    }

    private func fetchBackendEntitlement(
        accountScope: EntitlementAccountScope,
        generation: UInt64
    ) async {
        guard isCurrent(accountScope: accountScope, generation: generation) else { return }
        do {
            let response: EntitlementResponse = try await apiClient.send(Endpoints.getEntitlements())
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            backendEntitlement = response.entitlement
            updateDerivedState()
            try? store.set(response.entitlement, forKey: accountScope.cacheKey)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            log.warning("Entitlement backend fetch failed: \(Self.safeErrorCode(error))")
        }
    }

    private func fetchStoreKitStatus(
        accountScope: EntitlementAccountScope,
        generation: UInt64
    ) async {
        guard isCurrent(accountScope: accountScope, generation: generation) else { return }
        do {
            let status = try await storeKitService.currentSubscriptionStatus()
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            storeKitStatus = status
            updateDerivedState()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            log.warning("StoreKit status fetch failed: \(Self.safeErrorCode(error))")
        }
    }

    // MARK: - Cross-platform reconciliation (P4.7)

    /// Runs the reconciler and triggers Apple transaction verification if needed.
    ///
    /// Called as the last step of every `refresh()`. When the reconciler detects
    /// that StoreKit shows an active Apple subscription the backend hasn't processed
    /// (most commonly: a renewal that arrived before the server webhook fired),
    /// this method re-verifies the transaction and re-fetches the backend entitlement.
    private func reconcileAndVerifyIfNeeded(
        accountScope: EntitlementAccountScope,
        generation: UInt64
    ) async {
        guard isCurrent(accountScope: accountScope, generation: generation),
              let backend = backendEntitlement else { return }

        let action = reconciler.reconcile(
            backend: backend,
            storeKitActiveProductIds: storeKitStatus.activeProductIds,
            storeKitLatestExpiryDate: storeKitStatus.latestExpiryDate,
            backendPeriodEndDate: currentPeriodEnd,
            knownAppleProductIds: storeKitConfig.allProductIDs
        )

        guard case .triggerAppleVerify = action else { return }

        log.info("EntitlementService: reconciler triggered Apple verify")
        do {
            try await storeKitService.verifyCurrentEntitlements()
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            // Re-fetch the backend entitlement to reflect the newly processed transaction.
            await fetchBackendEntitlement(accountScope: accountScope, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(accountScope: accountScope, generation: generation) else { return }
            log.warning("Apple verification reconciliation failed: \(Self.safeErrorCode(error))")
        }
    }

    // MARK: - Listeners

    private func startStoreKitListener() {
        let storeKitService = storeKitService
        storeKitListenerTaskHandle.installIfEmpty(
            Task { [weak self, storeKitService] in
                let stream = await storeKitService.entitlementChanges()
                for await _ in stream {
                    await self?.refresh()
                }
            }
        )
    }

    private func startForegroundListener() {
        #if canImport(UIKit)
        foregroundListenerTaskHandle.installIfEmpty(
            Task { [weak self] in
                let notifications = NotificationCenter.default.notifications(
                    named: UIApplication.didBecomeActiveNotification
                )
                for await _ in notifications {
                    await self?.refresh()
                }
            }
        )
        #endif
    }

    // MARK: - Derived state

    private func updateDerivedState() {
        let backendIsPro = backendEntitlement.map { e in
            e.plan == .pro && e.proStatus == "active"
        } ?? false
        let newIsPro = backendIsPro
        let newCanStart = newIsPro || (backendEntitlement?.remainingFreeStarts ?? 0) > 0
        let newProSource = backendEntitlement?.proSource
        if isPro != newIsPro { isPro = newIsPro }
        if canStartNewBook != newCanStart { canStartNewBook = newCanStart }
        if proSource != newProSource { proSource = newProSource }
    }

    private func invalidateRefreshes() {
        accountGeneration &+= 1
        refreshFlightID &+= 1
        refreshRequestedDuringFlight = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func isCurrent(
        accountScope: EntitlementAccountScope,
        generation: UInt64
    ) -> Bool {
        !Task.isCancelled
            && self.accountScope == accountScope
            && accountGeneration == generation
    }

    static func safeErrorCode(_ error: any Error) -> String {
        guard let error = error as? AppError else { return "entitlement_operation_failed" }
        switch error {
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
}
