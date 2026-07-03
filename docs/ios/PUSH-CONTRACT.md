# Push Notification Contract (B2)

Conventions for how permission state is surfaced and consumed across the iOS codebase.

---

## Permission state lifecycle

```
OS status: notDetermined
    │
    ├─ suggest(trigger:) fires at a value moment
    │        │
    │        ▼
    │   NotificationPrimingCoordinator
    │   evaluates: hasPrimed == false && status == .notDetermined
    │        │
    │        ├─ shows NotificationPrimingView (priming sheet)
    │        │
    │        │   user taps "Enable"       user taps "Not Now"
    │        │        │                        │
    │        │        ▼                        ▼
    │        │   coordinator.accept()    coordinator.dismiss()
    │        │        │                  (marks hasPrimed, no OS prompt)
    │        │        ▼
    │        │   NotificationAuthorizer.requestAuthorization()
    │        │        │
    │        │        ▼
    │   OS prompt shown → user taps Allow / Don't Allow
    │
    ▼
OS status: authorized | denied | provisional
```

---

## Provisional path

For low-risk re-engagement content (e.g. a streak reminder delivered after the first
login), call `NotificationAuthorizer.requestProvisionalAuthorization()` directly —
no priming needed because provisional notifications are silent and never interrupt.

The provisional grant upgrades to full authorization when the user accepts the
priming sheet later.

---

## Denied recovery

When `authorizer.currentStatus()` returns `.denied`:
- Do **not** call `requestAuthorization()` — the OS ignores it.
- Present `NotificationDeniedView`, which deep-links to `UIApplication.openSettingsURLString`.

---

## Analytics event names

| Event | Fired when |
|---|---|
| `notification_priming_shown` | Priming sheet becomes visible |
| `notification_priming_accepted` | User taps "Enable" on priming sheet |
| `notification_priming_dismissed` | User taps "Not Now" on priming sheet |
| `notification_os_granted` | OS prompt → Allow |
| `notification_os_denied` | OS prompt → Don't Allow (or request errored) |
| `notification_provisional_granted` | Provisional authorization succeeded |

All events are fired through the shared `AnalyticsClient` injected into
`NotificationAuthorizer` and `NotificationPrimingCoordinator`.

---

## Rules for downstream consumers (P9.1, P9.3)

1. **Never call `UNUserNotificationCenter.requestAuthorization` directly.**
   Always go through `NotificationAuthorizer`.

2. **Never call `suggest(trigger:)` on first launch.**
   The coordinator enforces this (status will not be `.notDetermined` on first
   launch until a value moment occurs), but callers must choose a meaningful trigger.

3. **APNs token registration (P9.1)** may only proceed once
   `authorizer.currentStatus()` returns `.authorized` or `.provisional`.

4. **Local notification scheduling (P9.3)** follows the same gate.

5. **The `hasPrimed` flag persists in `UserDefaults.standard`.**
   Do not clear it except in account-reset / sign-out flows.
