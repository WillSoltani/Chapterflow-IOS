import Testing
import Models
import Accessibility
@testable import EngagementFeature

/// Unit tests for the audio graph summaries (`AXChartDescriptor.summary`) exposed
/// on all four Dashboard chart types. VoiceOver reads these strings when a user
/// requests an audio graph, so correctness matters for screen-reader users.
///
/// `@MainActor` is required because the chart types are SwiftUI views and therefore
/// main-actor-isolated; calling `makeChartDescriptor()` off the main actor triggers
/// a Swift 6 concurrency trap at runtime.
@MainActor @Suite("Chart Audio Graph Accessibility Descriptors")
struct ChartAudioGraphTests {

    // MARK: - WeeklyGoalChart

    @Test("WeeklyGoalChart — not met: summary includes read, goal and remaining minutes")
    func weeklyGoalNotMet() throws {
        let chart = WeeklyGoalChart(weeklyReadMinutes: 45, weeklyGoalMinutes: 120)
        let summary = try #require(chart.makeChartDescriptor().summary)
        #expect(summary.contains("45"))
        #expect(summary.contains("120"))
        #expect(summary.contains("75"))          // 120 − 45 = 75 remaining
        #expect(summary.contains("remaining"))
    }

    @Test("WeeklyGoalChart — met exactly: summary says goal met")
    func weeklyGoalMet() throws {
        let chart = WeeklyGoalChart(weeklyReadMinutes: 120, weeklyGoalMinutes: 120)
        let summary = try #require(chart.makeChartDescriptor().summary)
        #expect(summary.contains("Goal met"))
        #expect(summary.contains("120"))
    }

    @Test("WeeklyGoalChart — exceeded goal: summary reports goal met")
    func weeklyGoalExceeded() throws {
        let chart = WeeklyGoalChart(weeklyReadMinutes: 150, weeklyGoalMinutes: 120)
        let summary = try #require(chart.makeChartDescriptor().summary)
        #expect(summary.contains("Goal met"))
    }

    @Test("WeeklyGoalChart — zero goal: descriptor is non-nil and does not crash")
    func weeklyGoalZeroGoal() {
        let chart = WeeklyGoalChart(weeklyReadMinutes: 0, weeklyGoalMinutes: 0)
        #expect(chart.makeChartDescriptor().summary != nil)
    }

    // MARK: - ReadingTimeTrendChart

    @Test("ReadingTimeTrendChart — empty days list: summary reports no reading")
    func readingTimeTrendEmpty() throws {
        let chart = ReadingTimeTrendChart(days: [])
        let summary = try #require(chart.makeChartDescriptor().summary)
        #expect(summary.contains("No reading recorded"))
    }

    @Test("ReadingTimeTrendChart — all zero-minute days: summary reports no reading")
    func readingTimeTrendAllZeros() throws {
        let days: [StreakDay] = [
            StreakDay(date: "2026-07-01", minutesRead: 0),
            StreakDay(date: "2026-07-02", minutesRead: 0),
        ]
        let chart = ReadingTimeTrendChart(days: days)
        let summary = try #require(chart.makeChartDescriptor().summary)
        #expect(summary.contains("No reading recorded"))
    }

    @Test("ReadingTimeTrendChart — with data: summary includes total and peak minutes")
    func readingTimeTrendWithData() throws {
        let days: [StreakDay] = [
            StreakDay(date: "2026-07-01", minutesRead: 30),
            StreakDay(date: "2026-07-02", minutesRead: 45),
            StreakDay(date: "2026-07-03", minutesRead: 15),
        ]
        let chart = ReadingTimeTrendChart(days: days)
        let summary = try #require(chart.makeChartDescriptor().summary)
        // Total 90 min over 3 days; peak 45
        #expect(summary.contains("90"))
        #expect(summary.contains("45"))
        #expect(summary.contains("3"))
    }

    // MARK: - ChaptersProgressChart

    @Test("ChaptersProgressChart — empty items: summary is 'No data.'")
    func chaptersProgressEmpty() throws {
        let chart = ChaptersProgressChart(items: [])
        let summary = try #require(chart.makeChartDescriptor().summary)
        #expect(summary == "No data.")
    }

    @Test("ChaptersProgressChart — with items: summary includes chapter counts")
    func chaptersProgressWithItems() throws {
        let items: [ProgressOverviewItem] = [
            ProgressOverviewItem(
                bookId: "atomic-habits",
                currentChapterNumber: 8,
                totalChapters: 12,
                completedChapterCount: 8,
                lastReadAt: nil
            ),
        ]
        let chart = ChaptersProgressChart(items: items)
        let summary = try #require(chart.makeChartDescriptor().summary)
        #expect(summary.contains("8"))
        #expect(summary.contains("12"))
        #expect(summary.contains("chapters"))
    }

    @Test("ChaptersProgressChart — filters books with zero total chapters")
    func chaptersProgressZeroChapters() throws {
        let items: [ProgressOverviewItem] = [
            ProgressOverviewItem(
                bookId: "draft-book",
                currentChapterNumber: 0,
                totalChapters: 0,
                completedChapterCount: 0,
                lastReadAt: nil
            ),
        ]
        let chart = ChaptersProgressChart(items: items)
        let summary = try #require(chart.makeChartDescriptor().summary)
        // Book with 0 chapters is filtered out → treated as empty
        #expect(summary == "No data.")
    }
}
