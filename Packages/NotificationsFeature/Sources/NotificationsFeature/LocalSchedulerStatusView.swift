import SwiftUI
import Models
import DesignSystem

// MARK: - LocalSchedulerStatusView

/// A debug/settings view that shows which local notification kinds are currently
/// enabled and what they are scheduled to fire.
///
/// Intended for Settings → Notifications and `#Preview` usage.
public struct LocalSchedulerStatusView: View {
    private let prefs: NotificationPreferences
    private let cards: [FsrsCard]
    private let commitments: [Commitment]
    private let readToday: Bool
    private let now: Date

    public init(
        prefs: NotificationPreferences,
        cards: [FsrsCard] = [],
        commitments: [Commitment] = [],
        readToday: Bool = false,
        now: Date = Date()
    ) {
        self.prefs       = prefs
        self.cards       = cards
        self.commitments = commitments
        self.readToday   = readToday
        self.now         = now
    }

    public var body: some View {
        List {
            Section("Reading Reminders") {
                reminderRow(
                    title: "Daily reading",
                    detail: prefs.readingReminderEnabled
                        ? "Every day at \(prefs.readingReminderTime)"
                        : "Disabled",
                    enabled: prefs.readingReminderEnabled,
                    identifier: LocalNotificationID.dailyReading
                )

                reminderRow(
                    title: "Streak at risk",
                    detail: streakAtRiskDetail,
                    enabled: prefs.streakReminderEnabled && !readToday,
                    identifier: LocalNotificationID.streakAtRisk
                )
            }

            Section("Reviews") {
                reminderRow(
                    title: "Next review due",
                    detail: reviewDueDetail,
                    enabled: prefs.reviewReminderEnabled && nextDueCard != nil,
                    identifier: LocalNotificationID.reviewDue
                )
            }

            if !activeCommitments.isEmpty {
                Section("Commitment Follow-ups") {
                    ForEach(activeCommitments) { commitment in
                        reminderRow(
                            title: "Follow-up",
                            detail: commitment.ifStatement,
                            enabled: commitment.followUpDate > now,
                            identifier: LocalNotificationID.commitment(commitment.id)
                        )
                    }
                }
            }

            if prefs.quietHoursEnabled {
                Section("Quiet Hours") {
                    HStack {
                        Label("Quiet hours active", systemImage: "moon.fill")
                            .font(.subheadline)
                        Spacer()
                        Text("\(prefs.quietHoursStart) – \(prefs.quietHoursEnd)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Local Notifications")
    }

    // MARK: - Helpers

    private var nextDueCard: FsrsCard? {
        cards.compactMap { card in
            card.dueDate.map { (card, $0) }
        }
        .filter { $0.1 > now }
        .min(by: { $0.1 < $1.1 })
        .map(\.0)
    }

    private var activeCommitments: [Commitment] {
        commitments.filter { $0.status == .active }
    }

    private var streakAtRiskDetail: String {
        if readToday { return "Cancelled — you read today" }
        if !prefs.streakReminderEnabled { return "Disabled" }
        return "Today at 20:00 (if unread)"
    }

    private var reviewDueDetail: String {
        guard prefs.reviewReminderEnabled else { return "Disabled" }
        guard let card = nextDueCard, let due = card.dueDate else { return "No cards due" }
        let dueCount = cards.filter { c in c.dueDate.map { $0 <= due.addingTimeInterval(3600) } ?? (c.state == .new) }.count
        let formatted = due.formatted(date: .abbreviated, time: .shortened)
        return "\(dueCount) card\(dueCount == 1 ? "" : "s") · \(formatted)"
    }

    @ViewBuilder
    private func reminderRow(
        title: String,
        detail: String,
        enabled: Bool,
        identifier: String
    ) -> some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: enabled ? "bell.fill" : "bell.slash")
                .foregroundStyle(enabled ? Color.accentColor : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if enabled {
                Text(identifier.components(separatedBy: ".").last ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
    }
}

// MARK: - Previews

#Preview("Reminders enabled — light", traits: .sizeThatFitsLayout) {
    NavigationStack {
        LocalSchedulerStatusView(
            prefs: NotificationPreferences(
                readingReminderEnabled: true,
                readingReminderTime: "20:00",
                streakReminderEnabled: true,
                reviewReminderEnabled: true
            ),
            cards: PreviewData.sampleCards,
            commitments: PreviewData.sampleCommitments,
            readToday: false
        )
    }
}

#Preview("Read today — streak cancelled", traits: .sizeThatFitsLayout) {
    NavigationStack {
        LocalSchedulerStatusView(
            prefs: .default,
            cards: PreviewData.sampleCards,
            commitments: [],
            readToday: true
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Quiet hours active", traits: .sizeThatFitsLayout) {
    NavigationStack {
        LocalSchedulerStatusView(
            prefs: NotificationPreferences(
                readingReminderEnabled: true,
                readingReminderTime: "23:00",
                streakReminderEnabled: true,
                reviewReminderEnabled: true,
                quietHoursEnabled: true,
                quietHoursStart: "22:00",
                quietHoursEnd: "08:00"
            ),
            cards: PreviewData.sampleCards,
            commitments: PreviewData.sampleCommitments,
            readToday: false
        )
    }
}

#Preview("XXL Dynamic Type", traits: .sizeThatFitsLayout) {
    NavigationStack {
        LocalSchedulerStatusView(
            prefs: .default,
            cards: PreviewData.sampleCards,
            commitments: PreviewData.sampleCommitments,
            readToday: false
        )
    }
    .dynamicTypeSize(.accessibility2)
}

// MARK: - Preview data

private enum PreviewData {
    static let sampleCards: [FsrsCard] = {
        let tomorrow   = Date().addingTimeInterval(86400)
        let nextWeek   = Date().addingTimeInterval(7 * 86400)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [
            FsrsCard(
                cardId: "c1", bookId: "b1", chapterId: "ch1",
                front: "What is FSRS?", back: "Free Spaced Repetition Scheduler",
                dueAt: iso.string(from: tomorrow),
                stability: 1.3, difficulty: 5.0, state: .due,
                lastReviewAt: nil, reps: 2, lapses: 0,
                elapsedDays: 1, scheduledDays: 1, retrievability: 0.9
            ),
            FsrsCard(
                cardId: "c2", bookId: "b1", chapterId: "ch2",
                front: "Define spaced repetition", back: "A memorisation technique",
                dueAt: iso.string(from: nextWeek),
                stability: 3.0, difficulty: 4.0, state: .due,
                lastReviewAt: nil, reps: 3, lapses: 0,
                elapsedDays: 3, scheduledDays: 7, retrievability: 0.8
            )
        ]
    }()

    static let sampleCommitments: [Commitment] = [
        Commitment(
            id: "com-1",
            bookId: "b1",
            chapterId: "ch1",
            ifStatement: "I feel the urge to procrastinate",
            thenStatement: "I will read one chapter instead",
            followUpDate: Date().addingTimeInterval(3 * 86400),
            status: .active,
            outcome: nil,
            reflection: nil,
            createdAt: Date()
        )
    ]
}
