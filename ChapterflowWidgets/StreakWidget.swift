import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Provider

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StreakEntry) -> Void) {
        completion(StreakEntry(date: Date(), snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StreakEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let entry = StreakEntry(date: Date(), snapshot: snapshot)
        let nextRefresh = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Small View

struct StreakSmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: snapshot.streakAtRisk ? "flame" : "flame.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(snapshot.streakAtRisk ? Color.cfWidgetFlame.opacity(0.5) : Color.cfWidgetFlame)
                Spacer()
                if snapshot.streakShieldsHeld > 0 {
                    Label("\(snapshot.streakShieldsHeld)", systemImage: "shield.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.cfWidgetAccent)
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer()

            Text("\(snapshot.streakDays)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(snapshot.streakDays == 1 ? "day streak" : "days streak")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            if snapshot.streakAtRisk {
                Spacer(minLength: .wS4)
                Label("Read today!", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.wS16)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Medium View

struct StreakMediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: .wS16) {
            // Left column: flame + streak count
            VStack(alignment: .leading, spacing: .wS4) {
                Image(systemName: snapshot.streakAtRisk ? "flame" : "flame.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(snapshot.streakAtRisk ? Color.cfWidgetFlame.opacity(0.5) : Color.cfWidgetFlame)

                Spacer()

                Text("\(snapshot.streakDays)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text(snapshot.streakDays == 1 ? "day streak" : "days streak")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Right column: stats
            VStack(alignment: .leading, spacing: .wS8) {
                StreakStatRow(
                    icon: "trophy.fill",
                    color: .yellow,
                    label: "Best",
                    value: "\(max(snapshot.longestStreak, snapshot.streakDays))d"
                )
                StreakStatRow(
                    icon: "shield.fill",
                    color: Color.cfWidgetAccent,
                    label: "Shields",
                    value: "\(snapshot.streakShieldsHeld)"
                )

                Spacer()

                if snapshot.streakAtRisk {
                    Label("Read today to keep your streak!", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if snapshot.streakDays == 0 {
                    Text("Start your streak today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.wS16)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Lock Screen Views

struct StreakAccessoryCircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: snapshot.streakAtRisk ? "flame" : "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(snapshot.streakDays)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }
}

struct StreakAccessoryRectangularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: .wS4) {
            Image(systemName: snapshot.streakAtRisk ? "flame" : "flame.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("\(snapshot.streakDays) \(snapshot.streakDays == 1 ? "day" : "days") streak")
                .font(.system(size: 13, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Spacer()
            if snapshot.streakAtRisk {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct StreakAccessoryInlineView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Label(
            "\(snapshot.streakDays) \(snapshot.streakDays == 1 ? "day" : "day") streak\(snapshot.streakAtRisk ? " ⚠️" : "")",
            systemImage: "flame.fill"
        )
    }
}

// MARK: - Shared sub-view

struct StreakStatRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: .wS4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.weight(.semibold))
        }
    }
}

// MARK: - Widget

struct StreakWidget: Widget {
    static let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StreakProvider()) { entry in
            StreakWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Reading Streak")
        .description("Your current reading streak and at-risk indicator.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct StreakWidgetEntryView: View {
    let entry: StreakEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if !entry.snapshot.isAccountDataAvailable {
            WidgetAccountDataUnavailableView()
        } else {
            switch family {
            case .systemSmall:
                StreakSmallView(snapshot: entry.snapshot)
            case .systemMedium:
                StreakMediumView(snapshot: entry.snapshot)
            case .accessoryCircular:
                StreakAccessoryCircularView(snapshot: entry.snapshot)
            case .accessoryRectangular:
                StreakAccessoryRectangularView(snapshot: entry.snapshot)
            case .accessoryInline:
                StreakAccessoryInlineView(snapshot: entry.snapshot)
            default:
                StreakSmallView(snapshot: entry.snapshot)
            }
        }
    }
}

// MARK: - Previews

#Preview("Streak Small — Active", as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .placeholder)
}

#Preview("Streak Small — At Risk", as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: WidgetSnapshot(
        streakDays: 5, longestStreak: 14, streakShieldsHeld: 0,
        streakAtRisk: true, dueReviewCount: 2,
        dailyGoalMinutes: 20, goalProgressMinutes: 0, lastUpdated: .now
    ))
}

#Preview("Streak Medium", as: .systemMedium) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .placeholder)
}

#Preview("Streak accessoryCircular", as: .accessoryCircular) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .placeholder)
}

#Preview("Streak accessoryRectangular", as: .accessoryRectangular) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .placeholder)
}
