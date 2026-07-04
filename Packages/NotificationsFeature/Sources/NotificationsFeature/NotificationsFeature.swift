// NotificationsFeature — permission priming, APNs registration, and denied recovery.
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
public enum NotificationsFeature {
    public static let moduleName = "NotificationsFeature"
}
