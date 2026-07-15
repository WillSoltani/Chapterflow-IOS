import Testing
import Foundation
import CoreKit
@testable import NotificationsFeature

// MARK: - Mock authorizer

/// In-memory mock that never touches UNUserNotificationCenter.
final class MockNotificationAuthorizer: NotificationAuthorizerProtocol, @unchecked Sendable {
    var stubbedStatus: NotificationPermissionStatus = .notDetermined
    var stubbedOutcome: NotificationAuthorizationOutcome = .granted

    private(set) var requestAuthorizationCallCount = 0
    private(set) var requestProvisionalCallCount = 0
    private(set) var currentStatusCallCount = 0

    func currentStatus() async -> NotificationPermissionStatus {
        currentStatusCallCount += 1
        return stubbedStatus
    }

    func requestAuthorization() async -> NotificationAuthorizationOutcome {
        requestAuthorizationCallCount += 1
        return stubbedOutcome
    }

    func requestProvisionalAuthorization() async -> NotificationAuthorizationOutcome {
        requestProvisionalCallCount += 1
        return .provisional
    }
}

// MARK: - Helpers

@MainActor
private func makeCoordinator(
    status: NotificationPermissionStatus = .notDetermined,
    defaults: UserDefaults? = nil
) -> (NotificationPrimingCoordinator, MockNotificationAuthorizer) {
    let authorizer = MockNotificationAuthorizer()
    authorizer.stubbedStatus = status
    let suite = defaults ?? UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let coordinator = NotificationPrimingCoordinator(
        authorizer: authorizer,
        analytics: NoopAnalyticsClient(),
        defaults: suite
    )
    return (coordinator, authorizer)
}

// MARK: - Tests

@Suite("NotificationPrimingCoordinator")
struct NotificationPrimingCoordinatorTests {

    @Test("suggest shows priming when OS is notDetermined and not yet primed")
    @MainActor
    func suggestShowsPrimingWhenNotDetermined() async {
        let (coordinator, _) = makeCoordinator(status: .notDetermined)
        await coordinator.suggest(trigger: .firstChapterCompleted)
        #expect(coordinator.isPrimingVisible == true)
    }

    @Test("suggest does not show priming when already authorized")
    @MainActor
    func suggestNoOpWhenAuthorized() async {
        let (coordinator, _) = makeCoordinator(status: .authorized)
        await coordinator.suggest(trigger: .firstChapterCompleted)
        #expect(coordinator.isPrimingVisible == false)
    }

    @Test("suggest does not show priming when denied")
    @MainActor
    func suggestNoOpWhenDenied() async {
        let (coordinator, _) = makeCoordinator(status: .denied)
        await coordinator.suggest(trigger: .firstChapterCompleted)
        #expect(coordinator.isPrimingVisible == false)
    }

    @Test("suggest does not show priming when provisional")
    @MainActor
    func suggestNoOpWhenProvisional() async {
        let (coordinator, _) = makeCoordinator(status: .provisional)
        await coordinator.suggest(trigger: .firstChapterCompleted)
        #expect(coordinator.isPrimingVisible == false)
    }

    @Test("second suggest is a no-op after dismiss (hasPrimed gate)")
    @MainActor
    func suggestBlockedAfterDismiss() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let (coordinator, _) = makeCoordinator(defaults: defaults)
        await coordinator.suggest(trigger: .firstChapterCompleted)
        #expect(coordinator.isPrimingVisible == true)

        coordinator.dismiss()
        #expect(coordinator.isPrimingVisible == false)

        // A second suggestion must NOT re-show
        await coordinator.suggest(trigger: .firstChapterCompleted)
        #expect(coordinator.isPrimingVisible == false)
    }

    @Test("second suggest is a no-op after accept")
    @MainActor
    func suggestBlockedAfterAccept() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let (coordinator, _) = makeCoordinator(defaults: defaults)
        await coordinator.suggest(trigger: .firstChapterCompleted)
        _ = await coordinator.accept()

        await coordinator.suggest(trigger: .readingReminderSet)
        #expect(coordinator.isPrimingVisible == false)
    }

    @Test("dismiss hides priming sheet")
    @MainActor
    func dismissHidesPriming() async {
        let (coordinator, _) = makeCoordinator()
        await coordinator.suggest(trigger: .firstChapterCompleted)
        coordinator.dismiss()
        #expect(coordinator.isPrimingVisible == false)
    }

    @Test("accept hides sheet and calls requestAuthorization once")
    @MainActor
    func acceptCallsAuthorizer() async {
        let (coordinator, authorizer) = makeCoordinator()
        authorizer.stubbedOutcome = .granted

        await coordinator.suggest(trigger: .firstChapterCompleted)
        let outcome = await coordinator.accept()

        #expect(outcome == .granted)
        #expect(authorizer.requestAuthorizationCallCount == 1)
        #expect(coordinator.isPrimingVisible == false)
    }

    @Test("accept returns denied when OS denies")
    @MainActor
    func acceptReturnsDenied() async {
        let (coordinator, authorizer) = makeCoordinator()
        authorizer.stubbedOutcome = .denied

        await coordinator.suggest(trigger: .firstChapterCompleted)
        let outcome = await coordinator.accept()

        #expect(outcome == .denied)
        #expect(authorizer.requestAuthorizationCallCount == 1)
    }

    @Test("suggest works for readingReminderSet trigger")
    @MainActor
    func suggestWorksForReminderTrigger() async {
        let (coordinator, _) = makeCoordinator(status: .notDetermined)
        await coordinator.suggest(trigger: .readingReminderSet)
        #expect(coordinator.isPrimingVisible == true)
    }

    @Test("coordinator does NOT show priming on construction (no cold-start prompt)")
    @MainActor
    func noColdStartPrompt() {
        let (coordinator, _) = makeCoordinator()
        #expect(coordinator.isPrimingVisible == false)
    }
}
