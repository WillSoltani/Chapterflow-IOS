import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ReviewEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Provider

struct ReviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReviewEntry {
        ReviewEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ReviewEntry) -> Void) {
        completion(ReviewEntry(date: Date(), snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ReviewEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let entry = ReviewEntry(date: Date(), snapshot: snapshot)
        // Refresh every 15 minutes
        let next = Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Small View

struct ReviewSmallView: View {
    let snapshot: WidgetSnapshot

    private var dueLabel: String {
        let n = snapshot.dueReviewCount
        if n == 0 { return "All caught up!" }
        return n == 1 ? "1 card due" : "\(n) cards due"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "brain.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.cfWidgetAccent)
                Spacer()
                if snapshot.dueReviewCount > 0 {
                    Text("\(min(snapshot.dueReviewCount, 99))\(snapshot.dueReviewCount > 99 ? "+" : "")")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cfWidgetAccent, in: Capsule())
                }
            }

            Spacer()

            Text("\(snapshot.dueReviewCount)")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(snapshot.dueReviewCount > 0 ? Color.primary : Color.secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(dueLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if snapshot.dueReviewCount > 0 {
                Spacer(minLength: .wS8)
                Text("Review now →")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.cfWidgetAccent)
            }
        }
        .padding(.wS16)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "chapterflow://review"))
    }
}

// MARK: - Lock Screen Views

struct ReviewAccessoryCircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "brain.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(snapshot.dueReviewCount)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }
}

struct ReviewAccessoryRectangularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: .wS4) {
            Image(systemName: "brain.fill")
                .font(.caption)
                .foregroundStyle(Color.cfWidgetAccent)
            if snapshot.dueReviewCount == 0 {
                Text("All reviews done")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Text("\(snapshot.dueReviewCount) \(snapshot.dueReviewCount == 1 ? "card" : "cards") due")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
        }
    }
}

struct ReviewAccessoryInlineView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let count = snapshot.dueReviewCount
        Label(
            count == 0 ? "No reviews due" : "\(count) review\(count == 1 ? "" : "s") due",
            systemImage: "brain.fill"
        )
    }
}

// MARK: - Widget

struct NextReviewWidget: Widget {
    static let kind = "NextReviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ReviewProvider()) { entry in
            NextReviewEntryView(entry: entry)
        }
        .configurationDisplayName("Due Reviews")
        .description("See how many flashcards are ready for review.")
        .supportedFamilies([.systemSmall,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct NextReviewEntryView: View {
    let entry: ReviewEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            ReviewSmallView(snapshot: entry.snapshot)
        case .accessoryCircular:
            ReviewAccessoryCircularView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            ReviewAccessoryRectangularView(snapshot: entry.snapshot)
        case .accessoryInline:
            ReviewAccessoryInlineView(snapshot: entry.snapshot)
        default:
            ReviewSmallView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Previews

#Preview("Review Small — Due", as: .systemSmall) {
    NextReviewWidget()
} timeline: {
    ReviewEntry(date: .now, snapshot: .placeholder)
}

#Preview("Review Small — All Done", as: .systemSmall) {
    NextReviewWidget()
} timeline: {
    ReviewEntry(date: .now, snapshot: WidgetSnapshot(
        streakDays: 12, longestStreak: 30, streakShieldsHeld: 1,
        streakAtRisk: false, dueReviewCount: 0,
        dailyGoalMinutes: 20, goalProgressMinutes: 18, lastUpdated: .now
    ))
}

#Preview("Review accessoryCircular", as: .accessoryCircular) {
    NextReviewWidget()
} timeline: {
    ReviewEntry(date: .now, snapshot: .placeholder)
}

#Preview("Review accessoryRectangular", as: .accessoryRectangular) {
    NextReviewWidget()
} timeline: {
    ReviewEntry(date: .now, snapshot: .placeholder)
}
