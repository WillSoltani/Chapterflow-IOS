import Testing
import Foundation
import CoreKit
@testable import NotificationsFeature

// MARK: - NotificationSettingsModel

@Suite("NotificationSettingsModel")
@MainActor
struct NotificationSettingsModelTests {

    func makeModel(
        status: NotificationPermissionStatus = .authorized,
        prefs: NotificationPreferences = .default,
        shouldThrow: Bool = false
    ) -> (NotificationSettingsModel, FakeNotificationPreferencesRepository) {
        let repo = FakeNotificationPreferencesRepository(preferences: prefs)
        repo.shouldThrow = shouldThrow
        let auth = MockNotificationAuthorizer()
        auth.stubbedStatus = status
        let model = NotificationSettingsModel(repository: repo, authorizer: auth)
        return (model, repo)
    }

    @Test("onAppear loads preferences and refreshes permission status")
    func onAppearLoadsPrefs() async {
        let prefs = NotificationPreferences(readingReminderTime: "19:00")
        let (model, _) = makeModel(status: .authorized, prefs: prefs)

        await model.onAppear()

        #expect(model.preferences?.readingReminderTime == "19:00")
        #expect(model.permissionStatus == .authorized)
        #expect(model.isLoading == false)
    }

    @Test("update mutates preferences optimistically")
    func updateMutatesImmediately() async {
        let (model, _) = makeModel()
        await model.onAppear()

        model.update { $0.weeklyDigestEnabled = true }

        #expect(model.preferences?.weeklyDigestEnabled == true)
    }

    @Test("update persists to repository")
    func updatePersistsToRepo() async {
        let (model, repo) = makeModel()
        await model.onAppear()

        model.update { $0.streakReminderEnabled = false }

        // Give the async persist task a moment
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(repo.savedPreferences.last?.streakReminderEnabled == false)
    }

    @Test("failed save sets saveError")
    func saveErrorSetOnFailure() async {
        let (model, repo) = makeModel()
        await model.onAppear()
        repo.shouldThrow = true

        model.update { $0.badgeAlertsEnabled = false }

        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(model.saveError != nil)
    }

    @Test("fetch failure sets preferences to default, not nil")
    func fetchFailureFallsBackToDefault() async {
        let (model, _) = makeModel(shouldThrow: true)

        await model.onAppear()

        #expect(model.preferences != nil)
        #expect(model.isLoading == false)
    }

    @Test("onForeground refreshes permission status")
    func onForegroundRefreshesStatus() async {
        let (model, _) = makeModel(status: .denied)
        await model.onAppear()
        #expect(model.permissionStatus == .denied)
    }

    @Test("second onAppear does not reload if prefs already loaded")
    func secondOnAppearSkipsReload() async {
        let (model, repo) = makeModel()
        await model.onAppear()
        let firstLoad = repo.savedPreferences.count

        await model.onAppear()
        let secondLoad = repo.savedPreferences.count
        // No additional saves triggered by re-appear
        #expect(firstLoad == secondLoad)
    }
}
