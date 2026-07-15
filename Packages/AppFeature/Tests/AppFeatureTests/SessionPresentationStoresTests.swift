import AuthKit
import Foundation
import Persistence
import Testing
@testable import AppFeature

@Suite("Session presentation stores")
@MainActor
struct SessionPresentationStoresTests {
    private struct Owner: Codable, Equatable {
        let value: String
    }

    @Test("account A, account B, and guest never share lightweight state")
    func accountsAndGuestAreIsolated() throws {
        let suite = "com.chapterflow.tests.presentation-stores.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let config = makeTestValidatedConfig()
        let accountA = SessionPresentationStores.account(
            context: AccountContext(identity: try identity("account-a"), config: config),
            defaults: defaults
        )
        let accountB = SessionPresentationStores.account(
            context: AccountContext(identity: try identity("account-b"), config: config),
            defaults: defaults
        )
        let guest = SessionPresentationStores.guest(defaults: defaults)

        try accountA.keyValueStore.set(Owner(value: "a"), forKey: "recent-search")
        accountA.preferences.onboardingCompleted = true
        accountA.dailyGoalStore.dailyGoalMinutes = 20

        #expect(accountB.keyValueStore.value(Owner.self, forKey: "recent-search") == nil)
        #expect(guest.keyValueStore.value(Owner.self, forKey: "recent-search") == nil)
        #expect(!accountB.preferences.onboardingCompleted)
        #expect(!guest.preferences.onboardingCompleted)
        #expect(accountB.dailyGoalStore.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
        #expect(guest.dailyGoalStore.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
        #expect(defaults.object(forKey: "recent-search") == nil)
        #expect(defaults.object(forKey: "pref.onboardingCompleted") == nil)
        #expect(defaults.object(forKey: DailyGoalStore.goalKey) == nil)

        try accountB.keyValueStore.set(Owner(value: "b"), forKey: "recent-search")
        try guest.keyValueStore.set(Owner(value: "guest"), forKey: "recent-search")
        accountB.dailyGoalStore.dailyGoalMinutes = 30
        guest.dailyGoalStore.dailyGoalMinutes = 10

        #expect(accountA.keyValueStore.value(Owner.self, forKey: "recent-search") == Owner(value: "a"))
        #expect(accountB.keyValueStore.value(Owner.self, forKey: "recent-search") == Owner(value: "b"))
        #expect(guest.keyValueStore.value(Owner.self, forKey: "recent-search") == Owner(value: "guest"))
        #expect(accountA.dailyGoalStore.dailyGoalMinutes == 20)
        #expect(accountB.dailyGoalStore.dailyGoalMinutes == 30)
        #expect(guest.dailyGoalStore.dailyGoalMinutes == 10)
    }

    @Test("legacy ownerless daily goal remains dormant")
    func legacyDailyGoalIsNotAttributed() throws {
        let suite = "com.chapterflow.tests.presentation-goal-legacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(30, forKey: DailyGoalStore.goalKey)

        let config = makeTestValidatedConfig()
        let account = SessionPresentationStores.account(
            context: AccountContext(identity: try identity("account-a"), config: config),
            defaults: defaults
        )
        let guest = SessionPresentationStores.guest(defaults: defaults)

        #expect(account.dailyGoalStore.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
        #expect(guest.dailyGoalStore.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
        #expect(defaults.integer(forKey: DailyGoalStore.goalKey) == 30)
    }

    private func identity(_ subject: String) throws -> SessionIdentity {
        try #require(SessionIdentity(
            subject: subject,
            username: "Reader",
            email: nil,
            source: .cognitoUserPool
        ))
    }
}
