// NotificationsFeature — permission priming, APNs registration, denied recovery, and
// notification coordination (analytics, quiet hours, daily cap, deduplication, snooze).
//
// Wiring (P9.5 — permission priming):
//   1. Create `NotificationAuthorizer(analytics:)` at app startup (one instance).
//   2. Create `NotificationPrimingCoordinator(authorizer:analytics:)` on the model.
//   3. At a value moment, call `await coordinator.suggest(trigger:)`.
//   4. Present `NotificationPrimingView` when `coordinator.isPrimingVisible == true`.
//   5. When status is `.denied`, present `NotificationDeniedView` for recovery.
//
// Wiring (P9.1 — APNs registration):
//   1. Create `APNSRegistrationManager(authorizer:repository:)` in `AppModel`.
//   2. Wire `AppDelegate` callbacks to `APNSRegistrationBridge.shared`.
//   3. Call `manager.start()` after sign-in resolves.
//   4. Call `manager.handleSignOut()` on sign-out.
//   5. Display `PushStatusView` in Settings.
//
// Wiring (P9.7 — notification coordinator):
//   1. At app startup: `NotificationCoordinator.configure(analytics: analyticsClient)`.
//   2. Set `PushRoutingBridge.shared.notificationCoordinator = NotificationCoordinator.shared`.
//   3. Set `PushRoutingBridge.shared.onNotificationSnoozed` to call
//      `LocalNotificationScheduler.shared.snoozeRequest(identifier:content:until:)` with
//      `NotificationCoordinator.snoozeFireDate(from: Date())` as the target time.
//   4. In `AppDelegate.userNotificationCenter(_:willPresent:)`:
//      call `PushRoutingBridge.shared.willPresentNotification(notification)`.
//   `LocalNotificationScheduler.shared` is already wired to the shared coordinator.
//
// Wiring (P9.3 — local notification scheduling):
//   Call `LocalNotificationScheduler.shared.reschedule(input:)` from `AppModel`
//   whenever the user's state changes:
//     - On app launch / foreground resume (after prefs + reviews load)
//     - After a reading session ends → pass `readToday: true`
//     - After the review session completes → also call `cancelReviewReminder()`
//     - When prefs change (NotificationSettingsModel calls reschedule after every update)
//     - When a new commitment is created (CommitmentRepository triggers reschedule)
//   Call `cancelAll()` on sign-out.
public enum NotificationsFeature {
    public static let moduleName = "NotificationsFeature"
}
