import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Provider

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ProgressEntry) -> Void) {
        completion(ProgressEntry(date: Date(), snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ProgressEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let entry = ProgressEntry(date: Date(), snapshot: snapshot)
        // Refresh every 15 minutes during the day
        let next = Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Small View

struct ProgressSmallView: View {
    let snapshot: WidgetSnapshot

    private var minutesLabel: String {
        let remaining = max(0, snapshot.dailyGoalMinutes - snapshot.goalProgressMinutes)
        if snapshot.isDailyGoalMet { return "Goal met!" }
        return "\(remaining) min left"
    }

    var body: some View {
        VStack(spacing: .wS8) {
            ZStack {
                WidgetProgressRing(progress: snapshot.goalFraction, lineWidth: 8)
                VStack(spacing: 2) {
                    Text("\(snapshot.goalProgressMinutes)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, height: 70)

            VStack(spacing: 2) {
                Text(minutesLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.isDailyGoalMet ? Color.green : .primary)
                    .lineLimit(1)
                Text("of \(snapshot.dailyGoalMinutes) min goal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.wS12)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Lock Screen Views

struct ProgressAccessoryCircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            ProgressView(value: snapshot.goalFraction)
                .progressViewStyle(.circular)
                .tint(Color.cfWidgetAccent)
        }
    }
}

struct ProgressAccessoryRectangularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: .wS8) {
            ProgressView(value: snapshot.goalFraction)
                .progressViewStyle(.circular)
                .tint(Color.cfWidgetAccent)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("Daily Goal")
                    .font(.caption2.weight(.semibold))
                Text("\(snapshot.goalProgressMinutes) / \(snapshot.dailyGoalMinutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct ProgressAccessoryInlineView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Label(
            "\(snapshot.goalProgressMinutes)/\(snapshot.dailyGoalMinutes) min\(snapshot.isDailyGoalMet ? " ✓" : "")",
            systemImage: "circle.dotted.circle.fill"
        )
    }
}

// MARK: - Widget

struct ProgressRingWidget: Widget {
    static let kind = "ProgressRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ProgressProvider()) { entry in
            ProgressRingEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Goal")
        .description("Track your daily reading progress.")
        .supportedFamilies([.systemSmall,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct ProgressRingEntryView: View {
    let entry: ProgressEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if !entry.snapshot.isAccountDataAvailable {
            WidgetAccountDataUnavailableView()
        } else {
            switch family {
            case .systemSmall:
                ProgressSmallView(snapshot: entry.snapshot)
            case .accessoryCircular:
                ProgressAccessoryCircularView(snapshot: entry.snapshot)
            case .accessoryRectangular:
                ProgressAccessoryRectangularView(snapshot: entry.snapshot)
            case .accessoryInline:
                ProgressAccessoryInlineView(snapshot: entry.snapshot)
            default:
                ProgressSmallView(snapshot: entry.snapshot)
            }
        }
    }
}

// MARK: - Previews

#Preview("Progress Small — In Progress", as: .systemSmall) {
    ProgressRingWidget()
} timeline: {
    ProgressEntry(date: .now, snapshot: .placeholder)
}

#Preview("Progress Small — Goal Met", as: .systemSmall) {
    ProgressRingWidget()
} timeline: {
    ProgressEntry(date: .now, snapshot: WidgetSnapshot(
        streakDays: 12, longestStreak: 30, streakShieldsHeld: 1,
        streakAtRisk: false, dueReviewCount: 0,
        dailyGoalMinutes: 20, goalProgressMinutes: 22, lastUpdated: .now
    ))
}

#Preview("Progress accessoryCircular", as: .accessoryCircular) {
    ProgressRingWidget()
} timeline: {
    ProgressEntry(date: .now, snapshot: .placeholder)
}

#Preview("Progress accessoryRectangular", as: .accessoryRectangular) {
    ProgressRingWidget()
} timeline: {
    ProgressEntry(date: .now, snapshot: .placeholder)
}
