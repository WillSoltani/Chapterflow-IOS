import SwiftUI
import DesignSystem
import Persistence

/// Full-screen notification preferences editor.
///
/// Reads server prefs on appear; writes back optimistically on every toggle.
/// Also shows the current OS permission status and a deep link to system
/// Settings when the user has denied permission.
public struct NotificationSettingsView: View {

    @State private var model: NotificationSettingsModel

    public init(model: NotificationSettingsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Form {
            permissionSection
            if model.preferences != nil {
                channelSection
                remindersSection
                quietHoursSection
                alertsSection
                digestSection
            }
            if let error = model.saveError {
                saveErrorSection(error)
            }
        }
        .navigationTitle("Notification Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if model.isLoading && model.preferences == nil {
                ProgressView()
                    .accessibilityLabel("Loading notification settings")
            }
        }
        .task { await model.onAppear() }
        #if canImport(UIKit)
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await model.onForeground() }
        }
        #endif
    }

    // MARK: - Permission section

    private var permissionSection: some View {
        Section {
            HStack {
                Label(permissionLabel, systemImage: permissionIcon)
                    .foregroundStyle(Color.cfLabel)
                Spacer()
                Text(permissionLabel)
                    .font(.cfSubheadline)
                    .foregroundStyle(permissionColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Push permission status: \(permissionLabel)")

            if model.permissionStatus == .denied {
                Button {
                    model.openSystemNotificationSettings()
                } label: {
                    Label("Enable in iOS Settings", systemImage: "arrow.up.right")
                        .foregroundStyle(Color.cfAccent)
                }
                .accessibilityLabel("Open iOS Settings to enable push notifications")
                .accessibilityHint("Opens the Settings app")
            }
        } header: {
            Text("iOS Permission")
        } footer: {
            if model.permissionStatus == .denied {
                Text("ChapterFlow can't send notifications until you enable permission in iOS Settings.")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
            } else if model.permissionStatus == .provisional {
                Text("Notifications are delivered quietly until you allow them from a banner.")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
    }

    // MARK: - Channel section

    @ViewBuilder
    private var channelSection: some View {
        if let prefs = model.preferences {
            Section("Delivery Channels") {
                Toggle(isOn: Binding(
                    get: { prefs.channels.push },
                    set: { val in model.update { $0.channels.push = val } }
                )) {
                    Label("Push Notifications", systemImage: "bell.fill")
                }
                .accessibilityLabel("Push notifications \(prefs.channels.push ? "on" : "off")")

                Toggle(isOn: Binding(
                    get: { prefs.channels.email },
                    set: { val in model.update { $0.channels.email = val } }
                )) {
                    Label("Email Digests", systemImage: "envelope.fill")
                }
                .accessibilityLabel("Email digests \(prefs.channels.email ? "on" : "off")")
            }
        }
    }

    // MARK: - Reminders section

    @ViewBuilder
    private var remindersSection: some View {
        if let prefs = model.preferences {
            Section("Reminders") {
                Toggle(isOn: Binding(
                    get: { prefs.readingReminderEnabled },
                    set: { val in model.update { $0.readingReminderEnabled = val } }
                )) {
                    Label("Daily Reading Reminder", systemImage: "book.fill")
                }
                .accessibilityLabel("Daily reading reminder \(prefs.readingReminderEnabled ? "on" : "off")")

                if prefs.readingReminderEnabled {
                    reminderTimePicker(timeString: prefs.readingReminderTime)
                }

                Toggle(isOn: Binding(
                    get: { prefs.streakReminderEnabled },
                    set: { val in model.update { $0.streakReminderEnabled = val } }
                )) {
                    Label("Streak At-Risk Reminder", systemImage: "flame.fill")
                }
                .accessibilityLabel("Streak reminder \(prefs.streakReminderEnabled ? "on" : "off")")
            }
        }
    }

    @ViewBuilder
    private func reminderTimePicker(timeString currentTime: String) -> some View {
        let binding = Binding<Date>(
            get: { date(from: currentTime) },
            set: { newDate in
                let str = formatTime(from: newDate)
                model.update { $0.readingReminderTime = str }
            }
        )
        DatePicker(
            "Reminder Time",
            selection: binding,
            displayedComponents: .hourAndMinute
        )
        .accessibilityLabel("Daily reminder time")
    }

    // MARK: - Quiet hours section

    @ViewBuilder
    private var quietHoursSection: some View {
        if let prefs = model.preferences {
            Section {
                Toggle(isOn: Binding(
                    get: { prefs.quietHoursEnabled },
                    set: { val in model.update { $0.quietHoursEnabled = val } }
                )) {
                    Label("Quiet Hours", systemImage: "moon.fill")
                }
                .accessibilityLabel("Quiet hours \(prefs.quietHoursEnabled ? "on" : "off")")

                if prefs.quietHoursEnabled {
                    DatePicker(
                        "Start",
                        selection: Binding(
                            get: { date(from: prefs.quietHoursStart) },
                            set: { newDate in model.update { prefs in prefs.quietHoursStart = formatTime(from: newDate) } }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityLabel("Quiet hours start time")

                    DatePicker(
                        "End",
                        selection: Binding(
                            get: { date(from: prefs.quietHoursEnd) },
                            set: { newDate in model.update { prefs in prefs.quietHoursEnd = formatTime(from: newDate) } }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityLabel("Quiet hours end time")
                }
            } header: {
                Text("Quiet Hours")
            } footer: {
                if prefs.quietHoursEnabled {
                    Text("No notifications will be scheduled to fire between \(prefs.quietHoursStart) and \(prefs.quietHoursEnd). Reminders that fall in this window are moved to just after it ends.")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
        }
    }

    // MARK: - Alerts section

    @ViewBuilder
    private var alertsSection: some View {
        if let prefs = model.preferences {
            Section("Achievements & Social") {
                Toggle(isOn: Binding(
                    get: { prefs.badgeAlertsEnabled },
                    set: { val in model.update { $0.badgeAlertsEnabled = val } }
                )) {
                    Label("Badges & Tier Unlocks", systemImage: "star.fill")
                }
                .accessibilityLabel("Badge and tier alerts \(prefs.badgeAlertsEnabled ? "on" : "off")")
            }
        }
    }

    // MARK: - Digest section

    @ViewBuilder
    private var digestSection: some View {
        if let prefs = model.preferences {
            Section("Weekly Summary") {
                Toggle(isOn: Binding(
                    get: { prefs.weeklyDigestEnabled },
                    set: { val in model.update { $0.weeklyDigestEnabled = val } }
                )) {
                    Label("Weekly Reading Digest", systemImage: "chart.bar.fill")
                }
                .accessibilityLabel("Weekly digest \(prefs.weeklyDigestEnabled ? "on" : "off")")
            }
        }
    }

    // MARK: - Save error section

    private func saveErrorSection(_ error: Error) -> some View {
        Section {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)
                Text("Changes are saved on this device but need recovery before they can sync.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Save error: \(error.localizedDescription)")
        }
    }

    // MARK: - Permission helpers

    private var permissionLabel: String {
        switch model.permissionStatus {
        case .authorized:       return "Allowed"
        case .provisional:      return "Provisional"
        case .denied:           return "Denied"
        case .notDetermined:    return "Not Set"
        case .ephemeral:        return "Ephemeral"
        }
    }

    private var permissionIcon: String {
        switch model.permissionStatus {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied:                                return "bell.slash.fill"
        case .notDetermined:                         return "bell"
        }
    }

    private var permissionColor: Color {
        switch model.permissionStatus {
        case .authorized, .provisional, .ephemeral: return Color.cfAccent
        case .denied:                                return Color.orange
        case .notDetermined:                         return Color.cfSecondaryLabel
        }
    }

    // MARK: - Time conversion helpers

    private func date(from timeString: String) -> Date {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return Date() }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = parts[0]
        comps.minute = parts[1]
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func formatTime(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 20
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Notification Settings — light") {
    NavigationStack {
        NotificationSettingsView(
            model: NotificationSettingsModel(
                repository: FakeNotificationPreferencesRepository(),
                authorizer: PreviewNotificationAuthorizer(),
                pendingStore: KeyValueStore()
            )
        )
    }
}

#Preview("Notification Settings — dark, permission denied") {
    let repo = FakeNotificationPreferencesRepository(
        preferences: NotificationPreferences(
            readingReminderEnabled: true,
            readingReminderTime: "20:00",
            streakReminderEnabled: false,
            badgeAlertsEnabled: true,
            weeklyDigestEnabled: false
        )
    )
    let auth = PreviewNotificationAuthorizer(status: .denied)
    NavigationStack {
        NotificationSettingsView(
            model: NotificationSettingsModel(
                repository: repo,
                authorizer: auth,
                pendingStore: KeyValueStore()
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Notification Settings — XXL text") {
    NavigationStack {
        NotificationSettingsView(
            model: NotificationSettingsModel(
                repository: FakeNotificationPreferencesRepository(),
                authorizer: PreviewNotificationAuthorizer(),
                pendingStore: KeyValueStore()
            )
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
