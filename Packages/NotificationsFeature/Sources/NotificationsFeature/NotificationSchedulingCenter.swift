import Foundation
import UserNotifications

// MARK: - Protocol

/// Abstraction over `UNUserNotificationCenter` scheduling operations.
///
/// Injected into `LocalNotificationScheduler` so tests can assert on what
/// was scheduled without needing a real app bundle or OS authorization.
public protocol NotificationSchedulingCenter: Sendable {
    func isAuthorized() async -> Bool
    func addRequest(_ request: UNNotificationRequest) async throws
    func removeRequests(withIdentifiers ids: [String])
    func removeAllPendingRequests()
    func pendingRequests() async -> [UNNotificationRequest]
}

// MARK: - System (live) implementation

/// Delegates to `UNUserNotificationCenter.current()`.
public struct SystemNotificationSchedulingCenter: NotificationSchedulingCenter {
    public init() {}

    public func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    public func addRequest(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    public func removeRequests(withIdentifiers ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func removeAllPendingRequests() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    public func pendingRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
}

// MARK: - Spy (for tests and previews)

/// Records all scheduling operations. Thread-safe via `@unchecked Sendable` — access
/// from the `@MainActor` test suite only.
public final class SpyNotificationCenter: NotificationSchedulingCenter, @unchecked Sendable {

    // MARK: - Recorded operations

    /// All requests added since creation (not de-duped by identifier).
    public private(set) var addedRequests: [UNNotificationRequest] = []
    /// All identifier sets passed to `removeRequests(withIdentifiers:)`.
    public private(set) var removedIdentifierBatches: [[String]] = []

    /// The current simulated pending set (add inserts, remove deletes).
    private var _pending: [String: UNNotificationRequest] = [:]

    // MARK: - Configuration

    /// Whether `isAuthorized()` returns `true`. Defaults to `true`.
    public var authorizedStub: Bool = true

    // MARK: - Init

    public init(authorized: Bool = true) {
        self.authorizedStub = authorized
    }

    // MARK: - NotificationSchedulingCenter

    public func isAuthorized() async -> Bool { authorizedStub }

    public func addRequest(_ request: UNNotificationRequest) async throws {
        _pending[request.identifier] = request
        addedRequests.append(request)
    }

    public func removeRequests(withIdentifiers ids: [String]) {
        removedIdentifierBatches.append(ids)
        for id in ids { _pending.removeValue(forKey: id) }
    }

    public func removeAllPendingRequests() {
        removedIdentifierBatches.append(Array(_pending.keys))
        _pending.removeAll()
    }

    public func pendingRequests() async -> [UNNotificationRequest] {
        Array(_pending.values)
    }

    // MARK: - Convenience helpers for tests

    /// All identifiers currently in the simulated pending set.
    public var pendingIdentifiers: Set<String> { Set(_pending.keys) }

    /// `true` if the simulated pending set contains a request with the given identifier.
    public func hasPending(id: String) -> Bool { _pending[id] != nil }

    /// Resets all recorded state (useful between test cases sharing the same spy).
    public func reset() {
        addedRequests.removeAll()
        removedIdentifierBatches.removeAll()
        _pending.removeAll()
    }
}
