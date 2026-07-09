import SwiftUI
import Charts
import Accessibility
import Models
import DesignSystem

/// Horizontal bar chart of chapters completed per book (top 6 by completion count).
/// Data source: `[ProgressOverviewItem]`.
struct ChaptersProgressChart: View {
    let items: [ProgressOverviewItem]

    private struct BarItem: Identifiable {
        let id: String
        let shortTitle: String
        let completed: Int
        let remaining: Int
        let fraction: Double
    }

    private var barItems: [BarItem] {
        items
            .filter { $0.totalChapters > 0 }
            .sorted { $0.completedChapterCount > $1.completedChapterCount }
            .prefix(6)
            .map { item in
                BarItem(
                    id: item.bookId,
                    shortTitle: shortTitle(item.bookId),
                    completed: item.completedChapterCount,
                    remaining: item.totalChapters - item.completedChapterCount,
                    fraction: item.completionFraction
                )
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            if barItems.isEmpty {
                emptyState
            } else {
                chart
            }
        }
        .accessibilityLabel("Chapters completed by book chart. \(audioGraphSummary)")
    }

    private var audioGraphSummary: String {
        guard !barItems.isEmpty else { return "No data." }
        let parts = barItems.map { "\($0.shortTitle): \($0.completed) of \($0.completed + $0.remaining) chapters" }
        return parts.joined(separator: ". ")
    }

    private var chart: some View {
        Chart(barItems) { item in
            BarMark(
                x: .value("Chapters", item.completed),
                y: .value("Book", item.shortTitle)
            )
            .foregroundStyle(Color.cfAccent.gradient)
            .cornerRadius(4)
            .accessibilityLabel(item.shortTitle)
            .accessibilityValue("\(item.completed) of \(item.completed + item.remaining) chapters completed")

            BarMark(
                x: .value("Remaining", item.remaining),
                y: .value("Book", item.shortTitle)
            )
            .foregroundStyle(Color.cfFill)
            .cornerRadius(4)
            .accessibilityHidden(true)
        }
        .accessibilityChartDescriptor(self)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text("\(n)")
                            .font(.cfCaption2)
                            .foregroundStyle(Color.cfTertiaryLabel)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.cfCaption2)
                            .foregroundStyle(Color.cfSecondaryLabel)
                    }
                }
            }
        }
        .frame(height: CGFloat(barItems.count) * 36 + 20)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: .cfSpacing8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfTertiaryLabel)
                Text("Start a book to see progress")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            Spacer()
        }
        .frame(height: 100)
    }

    // MARK: - Helpers

    /// Truncates a bookId to a short display title (used until real titles are available via catalog join).
    private func shortTitle(_ bookId: String) -> String {
        // In production this is replaced by a catalog lookup; fallback to a truncated id.
        let parts = bookId.split(separator: "-")
        return parts.prefix(2).joined(separator: "-").capitalized
    }
}

// MARK: - Audio Graph (AXChartDescriptorRepresentable)

extension ChaptersProgressChart: @preconcurrency AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let maxChapters = barItems.map { $0.completed + $0.remaining }.max() ?? 1
        // Use book title as categorical x so AXDataPoint.x (String) maps correctly.
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Book",
            categoryOrder: barItems.map { $0.shortTitle }
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Chapters completed",
            range: 0...Double(max(maxChapters, 1)),
            gridlinePositions: []
        ) { v in v.isFinite ? "\(Int(v)) chapters" : "" }
        let series = AXDataSeriesDescriptor(
            name: "Chapters completed",
            isContinuous: false,
            dataPoints: barItems.map { item in
                AXDataPoint(
                    x: item.shortTitle,
                    y: Double(item.completed),
                    label: "\(item.completed) of \(item.completed + item.remaining)"
                )
            }
        )
        return AXChartDescriptor(
            title: "Chapters Completed",
            summary: audioGraphSummary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Preview

#Preview("ChaptersProgressChart") {
    let items: [ProgressOverviewItem] = [
        ProgressOverviewItem(bookId: "atomic-habits", currentChapterNumber: 8, totalChapters: 12, completedChapterCount: 8, lastReadAt: nil),
        ProgressOverviewItem(bookId: "deep-work", currentChapterNumber: 5, totalChapters: 10, completedChapterCount: 5, lastReadAt: nil),
        ProgressOverviewItem(bookId: "thinking-fast", currentChapterNumber: 3, totalChapters: 14, completedChapterCount: 3, lastReadAt: nil),
        ProgressOverviewItem(bookId: "psychology-of-money", currentChapterNumber: 2, totalChapters: 20, completedChapterCount: 2, lastReadAt: nil),
    ]
    ChaptersProgressChart(items: items)
        .padding(.cfSpacing16)
        .background(Color.cfGroupedBackground)
}
