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
/// - **Local StoreKit status** from ``StoreKitService`` — provides optimistic
///   `isPro = true` immediately after a purchase while the backend catches up.
///
/// Never writes unlocks or completions client-side. The merge model is read-only:
/// StoreKit flips `isPro` optimistically; backend truth wins on the next refresh.
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

    // MARK: - Private state

    private var backendEntitlement: Entitlement?
    private var storeKitStatus: SubscriptionStatus = .unknown

    // MARK: - Dependencies

    private let storeKitService: any StoreKitServicing
    private let apiClient: any APIClientProtocol
    private let store: KeyValueStore
    private let log = AppLog(category: .billing)

    /// Listener tasks are cancelled in `deinit`.
    /// `nonisolated(unsafe)` lets `deinit` cancel without a main-actor hop;
    /// safe because only written from `start()` (always on main actor) and
    /// `deinit` runs after all strong references are gone.
    nonisolated(unsafe) private var storeKitListenerTask: Task<Void, Never>?
    nonisolated(unsafe) private var foregroundListenerTask: Task<Void, Never>?

    // MARK: - Init

    /// Creates an `EntitlementService`.
    ///
    /// The initializer synchronously warms from the local cache so that
    /// offline reads return a useful state before the first network round-trip.
    /// Call ``start()`` once at app startup to begin background listeners and
    /// trigger an initial refresh.
    ///
    /// - Parameters:
    ///   - storeKitService: The StoreKit 2 service (from P4.1).
    ///   - apiClient: The authenticated API client.
    ///   - store: Key-value store for the offline entitlement cache.
    ///     Defaults to the App Group `UserDefaults` via `KeyValueStore()`.
    public init(
        storeKitService: any StoreKitServicing,
        apiClient: any APIClientProtocol,
        store: KeyValueStore = KeyValueStore()
    ) {
        self.storeKitService = storeKitService
        self.apiClient = apiClient
        self.store = store
        // Warm from cache — offline reads work before the first network fetch.
        self.backendEntitlement = store.value(Entitlement.self, forKey: Self.cacheKey)
        updateDerivedState()
    }

    nonisolated deinit {
        storeKitListenerTask?.cancel()
        foregroundListenerTask?.cancel()
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
        startStoreKitListener()
        startForegroundListener()
        Task { await refresh() }
    }

    // MARK: - Refresh

    /// Refreshes entitlement state from both the backend and StoreKit.
    ///
    /// On success, updates `isPro`, `canStartNewBook`, and the offline cache.
    /// On failure, keeps the last known state to avoid flickering.
    ///
    /// Public so callers (e.g., post-purchase flow) can trigger an explicit
    /// refresh without waiting for the next background cycle.
    public func refresh() async {
        await fetchBackendEntitlement()
        await fetchStoreKitStatus()
    }

    // MARK: - Private fetch

    private func fetchBackendEntitlement() async {
        do {
            let response: EntitlementResponse = try await apiClient.send(Endpoints.getEntitlements())
            backendEntitlement = response.entitlement
            updateDerivedState()
            try? store.set(response.entitlement, forKey: Self.cacheKey)
        } catch {
            log.warning("EntitlementService: backend fetch failed — \(error.localizedDescription)")
            // Keep the last known entitlement (cache or previous refresh).
        }
    }

    private func fetchStoreKitStatus() async {
        do {
            let status = try await storeKitService.currentSubscriptionStatus()
            storeKitStatus = status
            updateDerivedState()
        } catch {
            log.warning("EntitlementService: StoreKit status fetch failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Listeners

    private func startStoreKitListener() {
        guard storeKitListenerTask == nil else { return }
        let stream = storeKitService.entitlementChanges
        storeKitListenerTask = Task { [weak self] in
            for await _ in stream {
                await self?.refresh()
            }
        }
    }

    private func startForegroundListener() {
        guard foregroundListenerTask == nil else { return }
        #if canImport(UIKit)
        foregroundListenerTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: UIApplication.didBecomeActiveNotification
            )
            for await _ in notifications {
                await self?.refresh()
            }
        }
        #endif
    }

    // MARK: - Derived state

    private func updateDerivedState() {
        let backendIsPro = backendEntitlement.map { e in
            e.plan == .pro && e.proStatus == "active"
        } ?? false
        let newIsPro = backendIsPro || storeKitStatus.isPro
        let newCanStart = newIsPro || (backendEntitlement?.remainingFreeStarts ?? 0) > 0
        if isPro != newIsPro { isPro = newIsPro }
        if canStartNewBook != newCanStart { canStartNewBook = newCanStart }
    }
}
