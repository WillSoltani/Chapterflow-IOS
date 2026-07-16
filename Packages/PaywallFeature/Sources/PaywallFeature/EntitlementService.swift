import Foundation
import CoreKit
import Models
import Networking
import Persistence
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

enum EntitlementServiceLifecycleState: Sendable, Equatable {
    case idle
    case running
    case paused
    case stopped
}

struct EntitlementServiceLifecycleSnapshot: Sendable, Equatable {
    let state: EntitlementServiceLifecycleState
    let storeKitListenerStartCount: Int
    let foregroundListenerStartCount: Int
    let refreshTaskStartCount: Int
    let hasStoreKitListener: Bool
}

private struct EntitlementServiceTasks: Sendable {
    var storeKitListener: Task<Void, Never>?
    var foregroundListener: Task<Void, Never>?
    var refresh: Task<Void, Never>?

    mutating func takeAll() -> [Task<Void, Never>] {
        let retained = [storeKitListener, foregroundListener, refresh].compactMap { $0 }
        storeKitListener = nil
        foregroundListener = nil
        refresh = nil
        return retained
    }
}

/// The single source of truth for subscription access throughout the app.
///
/// Merges two inputs:
/// - **Backend entitlement** (`GET /book/me/entitlements`) — authoritative once the
///   server has processed an Apple transaction.
/// - **Local StoreKit status** from ``StoreKitService`` — provides optimistic
///   `isPro = true` immediately after a purchase while the backend catches up.
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

    // MARK: - Cache key

    private static let cacheKey = "com.chapterflow.entitlement.v1"

    // MARK: - Public state

    /// `true` when the user holds an active Pro subscription.
    ///
    /// `true` when either the backend confirms Pro with `proStatus == "active"`,
    /// OR the local StoreKit subscription is active (optimistic post-purchase bridge).
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
    private let reconciler = EntitlementReconciler()

    // MARK: - Dependencies

    private let storeKitService: any StoreKitServicing
    private let apiClient: any APIClientProtocol
    private let store: KeyValueStore
    private let storeKitConfig: StoreKitConfig
    private let log = AppLog(category: .billing)

    private let tasks = Mutex(EntitlementServiceTasks())
    private var lifecycleState: EntitlementServiceLifecycleState = .idle
    private var stateBeforePause: EntitlementServiceLifecycleState = .idle
    private var lifecycleGeneration = 0
    private var storeKitListenerStartCount = 0
    private var foregroundListenerStartCount = 0
    private var refreshTaskStartCount = 0

    // MARK: - Init

    /// Creates an `EntitlementService`.
    ///
    /// The initializer synchronously warms from the local cache so that
    /// offline reads return a useful state before the first network round-trip.
    /// Call ``start()`` once at app startup to begin background listeners and
    /// trigger an initial refresh.
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
        // Warm from cache — offline reads work before the first network fetch.
        self.backendEntitlement = store.value(Entitlement.self, forKey: Self.cacheKey)
        updateDerivedState()
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
        tasks.withLock { handles in
            handles.takeAll().forEach { $0.cancel() }
        }
    }

    var lifecycleSnapshotForTesting: EntitlementServiceLifecycleSnapshot {
        EntitlementServiceLifecycleSnapshot(
            state: lifecycleState,
            storeKitListenerStartCount: storeKitListenerStartCount,
            foregroundListenerStartCount: foregroundListenerStartCount,
            refreshTaskStartCount: refreshTaskStartCount,
            hasStoreKitListener: tasks.withLock { $0.storeKitListener != nil }
        )
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

    /// Starts background listeners and triggers an initial refresh.
    ///
    /// Call once at app startup (composition root). Idempotent — safe to call
    /// again after the app re-enters the foreground.
    public func start() {
        guard lifecycleState == .idle else { return }
        lifecycleState = .running
        startStoreKitListener()
        startForegroundListener()
        startRefreshTask()
    }

    /// Reversibly quiesces listeners and refresh work while retaining account state.
    public func pause() async {
        guard lifecycleState == .idle || lifecycleState == .running else { return }
        stateBeforePause = lifecycleState
        lifecycleState = .paused
        lifecycleGeneration &+= 1
        let retainedTasks = cancelTasks()
        await storeKitService.pause()
        await awaitTasks(retainedTasks)
    }

    /// Resumes this same instance after a failed sign-out attempt.
    public func resume() async {
        guard lifecycleState == .paused else { return }
        let generation = lifecycleGeneration
        let targetState = stateBeforePause
        await storeKitService.resume()
        guard lifecycleState == .paused, lifecycleGeneration == generation else { return }
        lifecycleGeneration &+= 1
        lifecycleState = targetState
        guard targetState == .running else { return }
        startStoreKitListener()
        startForegroundListener()
        startRefreshTask()
    }

    /// Permanently stops account-bound work and clears only in-memory authority.
    /// Account-scoped durable cache data remains available to the same account.
    public func stop() async {
        guard lifecycleState != .stopped else { return }
        lifecycleState = .stopped
        lifecycleGeneration &+= 1
        let retainedTasks = cancelTasks()
        await storeKitService.stop()
        await awaitTasks(retainedTasks)
        backendEntitlement = nil
        storeKitStatus = .unknown
        updateDerivedState()
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
        let generation = lifecycleGeneration
        guard acceptsWork(generation: generation) else { return }
        await fetchBackendEntitlement(generation: generation)
        guard acceptsWork(generation: generation) else { return }
        await fetchStoreKitStatus(generation: generation)
        guard acceptsWork(generation: generation) else { return }
        await reconcileAndVerifyIfNeeded(generation: generation)
    }

    // MARK: - Private fetch

    private func fetchBackendEntitlement(generation: Int) async {
        do {
            let response: EntitlementResponse = try await apiClient.send(Endpoints.getEntitlements())
            guard acceptsWork(generation: generation) else { return }
            backendEntitlement = response.entitlement
            updateDerivedState()
            try? store.set(response.entitlement, forKey: Self.cacheKey)
        } catch is CancellationError {
            return
        } catch {
            log.warning("EntitlementService: backend fetch failed — \(error.localizedDescription)")
        }
    }

    private func fetchStoreKitStatus(generation: Int) async {
        do {
            let status = try await storeKitService.currentSubscriptionStatus()
            guard acceptsWork(generation: generation) else { return }
            storeKitStatus = status
            updateDerivedState()
        } catch is CancellationError {
            return
        } catch StoreKitServiceError.inactive {
            return
        } catch {
            log.warning("EntitlementService: StoreKit status fetch failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Cross-platform reconciliation (P4.7)

    /// Runs the reconciler and triggers Apple transaction verification if needed.
    ///
    /// Called as the last step of every `refresh()`. When the reconciler detects
    /// that StoreKit shows an active Apple subscription the backend hasn't processed
    /// (most commonly: a renewal that arrived before the server webhook fired),
    /// this method re-verifies the transaction and re-fetches the backend entitlement.
    private func reconcileAndVerifyIfNeeded(generation: Int) async {
        guard acceptsWork(generation: generation) else { return }
        guard let backend = backendEntitlement else { return }

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
            guard acceptsWork(generation: generation) else { return }
            // Re-fetch the backend entitlement to reflect the newly processed transaction.
            await fetchBackendEntitlement(generation: generation)
        } catch is CancellationError {
            return
        } catch StoreKitServiceError.inactive {
            return
        } catch {
            log.warning("EntitlementService: Apple verify during reconciliation failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Listeners

    private func startStoreKitListener() {
        guard lifecycleState == .running,
              tasks.withLock({ $0.storeKitListener == nil }) else { return }
        let stream = storeKitService.entitlementChanges
        storeKitListenerStartCount += 1
        let task = Task { [weak self] in
            for await _ in stream {
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
        tasks.withLock { $0.storeKitListener = task }
    }

    private func startForegroundListener() {
        guard lifecycleState == .running,
              tasks.withLock({ $0.foregroundListener == nil }) else { return }
        #if canImport(UIKit)
        foregroundListenerStartCount += 1
        let task = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: UIApplication.didBecomeActiveNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
        tasks.withLock { $0.foregroundListener = task }
        #endif
    }

    private func startRefreshTask() {
        guard lifecycleState == .running,
              tasks.withLock({ $0.refresh == nil }) else { return }
        refreshTaskStartCount += 1
        let generation = lifecycleGeneration
        let task = Task { [weak self] in
            guard let self, self.acceptsWork(generation: generation) else { return }
            await self.refresh()
        }
        tasks.withLock { $0.refresh = task }
    }

    private func cancelTasks() -> [Task<Void, Never>] {
        let retainedTasks = tasks.withLock { $0.takeAll() }
        retainedTasks.forEach { $0.cancel() }
        return retainedTasks
    }

    private func awaitTasks(_ retainedTasks: [Task<Void, Never>]) async {
        for task in retainedTasks {
            await task.value
        }
    }

    private func acceptsWork(generation: Int) -> Bool {
        generation == lifecycleGeneration &&
            lifecycleState != .paused && lifecycleState != .stopped
    }

    // MARK: - Derived state

    private func updateDerivedState() {
        let backendIsPro = backendEntitlement.map { e in
            e.plan == .pro && e.proStatus == "active"
        } ?? false
        let newIsPro = backendIsPro || storeKitStatus.isPro
        let newCanStart = newIsPro || (backendEntitlement?.remainingFreeStarts ?? 0) > 0
        let newProSource = backendEntitlement?.proSource
        if isPro != newIsPro { isPro = newIsPro }
        if canStartNewBook != newCanStart { canStartNewBook = newCanStart }
        if proSource != newProSource { proSource = newProSource }
    }
}
