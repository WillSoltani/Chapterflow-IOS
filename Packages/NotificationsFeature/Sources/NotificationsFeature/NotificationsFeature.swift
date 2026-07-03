// NotificationsFeature — permission priming, authorization, and denied recovery.
//
// Wiring:
//   1. Create `NotificationAuthorizer(analytics:)` at app startup (one instance).
//   2. Create `NotificationPrimingCoordinator(authorizer:analytics:)` on the model.
//   3. At a value moment, call `await coordinator.suggest(trigger:)`.
//   4. Present `NotificationPrimingView` when `coordinator.isPrimingVisible == true`.
//   5. When status is `.denied`, present `NotificationDeniedView` for recovery.
//   6. P9.1 (APNs) calls `authorizer.requestAuthorization()` through the coordinator.
public enum NotificationsFeature {
    public static let moduleName = "NotificationsFeature"
}
