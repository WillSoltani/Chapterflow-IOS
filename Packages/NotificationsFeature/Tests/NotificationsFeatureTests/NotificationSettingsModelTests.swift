import Testing
import Foundation
import CoreKit
import Persistence
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
        let defaults = UserDefaults(
            suiteName: "NotificationSettingsModelTests.\(UUID().uuidString)"
        )!
        let model = NotificationSettingsModel(
            repository: repo,
            authorizer: auth,
            pendingStore: KeyValueStore(defaults: defaults, keyPrefix: "account.test.")
        )
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

        await model.waitForPendingSave()

        #expect(repo.savedPreferences.last?.streakReminderEnabled == false)
    }

    @Test("failed save sets saveError")
    func saveErrorSetOnFailure() async {
        let (model, repo) = makeModel()
        await model.onAppear()
        repo.shouldThrow = true

        model.update { $0.badgeAlertsEnabled = false }

        await model.waitForPendingSave()

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

    @Test("cancelAndReset clears account-private settings state")
    func resetClearsState() async {
        let (model, repo) = makeModel(status: .authorized)
        await model.onAppear()
        repo.shouldThrow = true
        model.update { $0.badgeAlertsEnabled = false }
        await model.waitForPendingSave()
        #expect(model.saveError != nil)

        await model.cancelAndReset()

        #expect(model.preferences == nil)
        #expect(model.isLoading == false)
        #expect(model.saveError == nil)
        #expect(model.permissionStatus == .notDetermined)
    }

    @Test("cancelled save is retained and quarantined for its owning account")
    func cancelledSaveIsRetainedAndQuarantinedForOwningAccountOnly() async {
        let defaults = UserDefaults(
            suiteName: "NotificationSettingsModelTests.\(UUID().uuidString)"
        )!
        let accountAStore = KeyValueStore(defaults: defaults, keyPrefix: "account.a.")
        let accountBStore = KeyValueStore(defaults: defaults, keyPrefix: "account.b.")
        let authorizer = MockNotificationAuthorizer()
        let blockedRepository = BlockingPreferencesRepository()
        let modelA = NotificationSettingsModel(
            repository: blockedRepository,
            authorizer: authorizer,
            pendingStore: accountAStore
        )
        await modelA.onAppear()

        modelA.update { $0.weeklyDigestEnabled = true }
        await blockedRepository.waitForSaveStart()
        modelA.update { $0.badgeAlertsEnabled = false }

        await modelA.cancelAndReset()
        #expect(await blockedRepository.observedCancellation())

        let retained = accountAStore.value(
            NotificationPreferences.self,
            forKey: NotificationSettingsModel.pendingPreferencesKey
        )
        #expect(retained?.weeklyDigestEnabled == true)
        #expect(retained?.badgeAlertsEnabled == false)

        let accountBRepository = FakeNotificationPreferencesRepository()
        let modelB = NotificationSettingsModel(
            repository: accountBRepository,
            authorizer: authorizer,
            pendingStore: accountBStore
        )
        await modelB.onAppear()
        #expect(modelB.preferences?.badgeAlertsEnabled == true)
        #expect(accountBRepository.savedPreferences.isEmpty)

        let accountAReplayRepository = FakeNotificationPreferencesRepository()
        let restoredModelA = NotificationSettingsModel(
            repository: accountAReplayRepository,
            authorizer: authorizer,
            pendingStore: accountAStore
        )
        await restoredModelA.onAppear()

        #expect(restoredModelA.preferences?.weeklyDigestEnabled == true)
        #expect(restoredModelA.preferences?.badgeAlertsEnabled == false)
        #expect(accountAReplayRepository.savedPreferences.isEmpty)

        restoredModelA.update { $0.streakReminderEnabled = false }
        await Task.yield()
        #expect(accountAReplayRepository.savedPreferences.isEmpty)
        #expect(
            accountAStore.value(
                NotificationPreferences.self,
                forKey: NotificationSettingsModel.pendingPreferencesKey
            )?.streakReminderEnabled == false
        )
        #expect(accountAStore.contains(NotificationSettingsModel.pendingPreferencesKey))
    }

    @Test("rapid updates serialize delivery and leave the latest value authoritative")
    func rapidUpdatesSerializeLatestValue() async {
        let defaults = UserDefaults(
            suiteName: "NotificationSettingsModelTests.\(UUID().uuidString)"
        )!
        let store = KeyValueStore(defaults: defaults, keyPrefix: "account.a.")
        let repository = ControlledPreferencesRepository()
        let model = NotificationSettingsModel(
            repository: repository,
            authorizer: MockNotificationAuthorizer(),
            pendingStore: store
        )
        await model.onAppear()

        model.update { $0.weeklyDigestEnabled = true }
        await repository.waitForStartCount(1)

        model.update { $0.badgeAlertsEnabled = false }
        let startsWhileFirstIsBlocked = await repository.startCount()
        #expect(startsWhileFirstIsBlocked == 1)

        await repository.releaseSave(at: 0)
        await repository.waitForStartCount(2)
        let delivered = await repository.startedPreferences()
        #expect(delivered[0].weeklyDigestEnabled == true)
        #expect(delivered[0].badgeAlertsEnabled == true)
        #expect(delivered[1].weeklyDigestEnabled == true)
        #expect(delivered[1].badgeAlertsEnabled == false)

        await repository.releaseSave(at: 1)
        await model.waitForPendingSave()
        #expect(store.contains(NotificationSettingsModel.pendingPreferencesKey) == false)
    }
}

private actor BlockingPreferencesRepository: NotificationPreferencesRepository {
    private var saveStarted = false
    private var wasCancelled = false

    func fetchPreferences() async throws -> NotificationPreferences {
        .default
    }

    func savePreferences(_ preferences: NotificationPreferences) async throws {
        saveStarted = true
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }

    func waitForSaveStart() async {
        while !saveStarted {
            await Task.yield()
        }
    }

    func observedCancellation() -> Bool {
        wasCancelled
    }
}

private actor ControlledPreferencesRepository: NotificationPreferencesRepository {
    private var started: [NotificationPreferences] = []
    private var releases: [CheckedContinuation<Void, Never>?] = []

    func fetchPreferences() async throws -> NotificationPreferences {
        .default
    }

    func savePreferences(_ preferences: NotificationPreferences) async throws {
        started.append(preferences)
        await withCheckedContinuation { continuation in
            releases.append(continuation)
        }
    }

    func waitForStartCount(_ count: Int) async {
        while started.count < count {
            await Task.yield()
        }
    }

    func startCount() -> Int {
        started.count
    }

    func startedPreferences() -> [NotificationPreferences] {
        started
    }

    func releaseSave(at index: Int) {
        guard releases.indices.contains(index), let continuation = releases[index] else { return }
        releases[index] = nil
        continuation.resume()
    }
}
