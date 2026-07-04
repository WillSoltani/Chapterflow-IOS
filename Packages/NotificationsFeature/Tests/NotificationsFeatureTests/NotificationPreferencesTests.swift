import Testing
import Foundation
import CoreKit
import Networking
@testable import NotificationsFeature

// MARK: - NotificationPreferences decoding

@Suite("NotificationPreferences")
struct NotificationPreferencesTests {

    // MARK: - Decoding

    @Test("decodes fully-specified JSON")
    func decodesFullJSON() throws {
        let json = """
        {
            "channels": { "push": true, "email": false },
            "readingReminderEnabled": true,
            "readingReminderTime": "21:30",
            "streakReminderEnabled": false,
            "badgeAlertsEnabled": true,
            "weeklyDigestEnabled": true
        }
        """.data(using: .utf8)!

        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: json)
        #expect(prefs.channels.push == true)
        #expect(prefs.channels.email == false)
        #expect(prefs.readingReminderEnabled == true)
        #expect(prefs.readingReminderTime == "21:30")
        #expect(prefs.streakReminderEnabled == false)
        #expect(prefs.badgeAlertsEnabled == true)
        #expect(prefs.weeklyDigestEnabled == true)
    }

    @Test("missing fields fall back to defaults — no crash")
    func missingFieldsFallback() throws {
        let json = "{}".data(using: .utf8)!
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: json)
        // Should use default values — no throw
        #expect(prefs.readingReminderEnabled == true)
        #expect(prefs.channels.push == true)
    }

    @Test("partially-specified JSON fills rest with defaults")
    func partialJSON() throws {
        let json = """
        { "readingReminderTime": "07:00", "weeklyDigestEnabled": true }
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: json)
        #expect(prefs.readingReminderTime == "07:00")
        #expect(prefs.weeklyDigestEnabled == true)
        #expect(prefs.streakReminderEnabled == true)  // default
    }
}

// MARK: - FakeNotificationPreferencesRepository

@Suite("FakeNotificationPreferencesRepository")
struct FakePreferencesRepoTests {

    @Test("fetchPreferences returns stubbed prefs")
    func fetchReturnsStubbedPrefs() async throws {
        let prefs = NotificationPreferences(readingReminderTime: "09:00")
        let repo = FakeNotificationPreferencesRepository(preferences: prefs)
        let fetched = try await repo.fetchPreferences()
        #expect(fetched.readingReminderTime == "09:00")
    }

    @Test("savePreferences records the saved prefs")
    func saveRecordsPrefs() async throws {
        let repo = FakeNotificationPreferencesRepository()
        var updated = NotificationPreferences.default
        updated.streakReminderEnabled = false
        try await repo.savePreferences(updated)
        #expect(repo.savedPreferences.count == 1)
        #expect(repo.savedPreferences.first?.streakReminderEnabled == false)
    }

    @Test("shouldThrow causes fetch to throw AppError.offline")
    func shouldThrowOnFetch() async {
        let repo = FakeNotificationPreferencesRepository()
        repo.shouldThrow = true
        do {
            _ = try await repo.fetchPreferences()
            Issue.record("Expected throw")
        } catch let error as AppError {
            if case .offline = error { /* expected */ } else {
                Issue.record("Wrong AppError case: \(error)")
            }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("shouldThrow causes save to throw AppError.offline")
    func shouldThrowOnSave() async {
        let repo = FakeNotificationPreferencesRepository()
        repo.shouldThrow = true
        do {
            try await repo.savePreferences(.default)
            Issue.record("Expected throw")
        } catch let error as AppError {
            if case .offline = error { /* expected */ } else {
                Issue.record("Wrong AppError case: \(error)")
            }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}

// MARK: - LiveNotificationPreferencesRepository (via MockAPIClient)

@Suite("LiveNotificationPreferencesRepository")
struct LivePreferencesRepoTests {

    @Test("fetchPreferences decodes the notifications block from settings")
    func fetchDecodes() async throws {
        let json = """
        {
            "notifications": {
                "channels": { "push": true, "email": true },
                "readingReminderEnabled": false,
                "readingReminderTime": "08:00",
                "streakReminderEnabled": true,
                "badgeAlertsEnabled": false,
                "weeklyDigestEnabled": false
            }
        }
        """.data(using: .utf8)!

        let mockClient = MockAPIClient()
        await mockClient.setStub(.success(json), for: "/book/me/settings")

        let repo = LiveNotificationPreferencesRepository(apiClient: mockClient)
        let prefs = try await repo.fetchPreferences()
        #expect(prefs.readingReminderEnabled == false)
        #expect(prefs.readingReminderTime == "08:00")
        #expect(prefs.badgeAlertsEnabled == false)
    }

    @Test("fetchPreferences returns default when notifications block absent")
    func fetchDefaultWhenMissing() async throws {
        let json = "{}".data(using: .utf8)!
        let mockClient = MockAPIClient()
        await mockClient.setStub(.success(json), for: "/book/me/settings")

        let repo = LiveNotificationPreferencesRepository(apiClient: mockClient)
        let prefs = try await repo.fetchPreferences()
        #expect(prefs == .default)
    }

    @Test("savePreferences sends PATCH to /book/me/settings")
    func saveSendsPatch() async throws {
        let mockClient = MockAPIClient()
        await mockClient.setStub(.success("{}".data(using: .utf8)!), for: "/book/me/settings")

        let repo = LiveNotificationPreferencesRepository(apiClient: mockClient)
        var prefs = NotificationPreferences.default
        prefs.weeklyDigestEnabled = true
        try await repo.savePreferences(prefs)

        let recorded = await mockClient.recordedEndpoints
        let patchCall = recorded.first { $0.method == .patch && $0.path == "/book/me/settings" }
        #expect(patchCall != nil)
    }
}
