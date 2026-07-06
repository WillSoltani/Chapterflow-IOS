import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ContinueEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Provider

struct ContinueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueEntry {
        ContinueEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ContinueEntry) -> Void) {
        completion(ContinueEntry(date: Date(), snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ContinueEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let entry = ContinueEntry(date: Date(), snapshot: snapshot)
        // Refresh every 30 minutes
        let next = Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Cover View

struct BookCoverView: View {
    let emoji: String?
    let color: String?
    let size: CGFloat

    private var bgColor: Color {
        Color(hexString: color) ?? Color.cfWidgetAccent.opacity(0.8)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.14)
                .fill(bgColor)
            Text(emoji ?? "📖")
                .font(.system(size: size * 0.52))
        }
        .frame(width: size, height: size * 1.3)
    }
}

// MARK: - Progress Ring (widget-local)

struct WidgetProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.cfWidgetAccent.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.cfWidgetAccent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Medium View

struct ContinueMediumView: View {
    let snapshot: WidgetSnapshot

    private var deepLink: URL? {
        guard let id = snapshot.continueBookId,
              let chapter = snapshot.continueChapterNumber
        else { return nil }
        return URL(string: "chapterflow://book/\(id)/chapter/\(chapter)")
    }

    var body: some View {
        if snapshot.hasContinueReading {
            readingContent
        } else {
            emptyState
        }
    }

    private var readingContent: some View {
        HStack(spacing: .wS12) {
            // Cover
            BookCoverView(
                emoji: snapshot.continueBookCoverEmoji,
                color: snapshot.continueBookCoverColor,
                size: 56
            )
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

            // Info
            VStack(alignment: .leading, spacing: .wS4) {
                Text("Continue Reading")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.cfWidgetAccent)
                    .textCase(.uppercase)
                    .tracking(0.3)

                Text(snapshot.continueBookTitle ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let chapter = snapshot.continueChapterNumber {
                    Text("Chapter \(chapter)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Progress bar
                if let progress = snapshot.continueProgress {
                    VStack(alignment: .leading, spacing: 2) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.cfWidgetAccent.opacity(0.15))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.cfWidgetAccent)
                                    .frame(width: geo.size.width * progress, height: 4)
                            }
                        }
                        .frame(height: 4)
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.wS16)
        .containerBackground(.background, for: .widget)
        .widgetURL(deepLink)
    }

    private var emptyState: some View {
        VStack(spacing: .wS8) {
            Image(systemName: "book.closed.fill")
                .font(.title)
                .foregroundStyle(Color.cfWidgetAccent.opacity(0.4))
            Text("Open ChapterFlow to start reading")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.wS16)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Widget

struct ContinueReadingWidget: Widget {
    static let kind = "ContinueReadingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ContinueProvider()) { entry in
            ContinueMediumView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Continue Reading")
        .description("Pick up where you left off.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview("Continue Reading — Active", as: .systemMedium) {
    ContinueReadingWidget()
} timeline: {
    ContinueEntry(date: .now, snapshot: .placeholder)
}

#Preview("Continue Reading — Empty", as: .systemMedium) {
    ContinueReadingWidget()
} timeline: {
    ContinueEntry(date: .now, snapshot: WidgetSnapshot(
        streakDays: 0, longestStreak: 0, streakShieldsHeld: 0,
        streakAtRisk: false, dueReviewCount: 0,
        dailyGoalMinutes: 20, goalProgressMinutes: 0, lastUpdated: .now
    ))
}

#Preview("Continue Reading — Dark", as: .systemMedium) {
    ContinueReadingWidget()
} timeline: {
    ContinueEntry(date: .now, snapshot: .placeholder)
}
