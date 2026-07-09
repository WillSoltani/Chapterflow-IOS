import SwiftUI
import Charts
import Accessibility
import Models
import DesignSystem

/// Bar chart showing daily minutes read over the last 14 days.
/// Data source: `StreakState.streakHistory`.
struct ReadingTimeTrendChart: View {
    let days: [StreakDay]

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let label: String
        let minutes: Int
        let date: Date
    }

    private var points: [ChartPoint] {
        days.compactMap { day -> ChartPoint? in
            guard let date = isoDate(day.date) else { return nil }
            return ChartPoint(
                label: dayLabel(date),
                minutes: day.minutesRead,
                date: date
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            if points.isEmpty {
                emptyState
            } else {
                chart
            }
        }
        .accessibilityLabel("Daily reading time chart. \(audioGraphSummary)")
    }

    private var audioGraphSummary: String {
        let total = points.reduce(0) { $0 + $1.minutes }
        guard let peak = points.max(by: { $0.minutes < $1.minutes }), peak.minutes > 0 else {
            return "No reading recorded."
        }
        return "Total \(total) minutes over \(points.count) days. Peak: \(peak.minutes) min on \(peak.label)."
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.label),
                y: .value("Minutes", point.minutes)
            )
            .foregroundStyle(
                point.minutes > 0
                    ? Color.cfAccent.gradient
                    : Color.cfFill.gradient
            )
            .cornerRadius(4)
            .accessibilityLabel("\(point.label)")
            .accessibilityValue(point.minutes > 0 ? "\(point.minutes) minutes" : "No reading")
        }
        .accessibilityChartDescriptor(self)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let mins = value.as(Int.self) {
                        Text("\(mins)m")
                            .font(.cfCaption2)
                            .foregroundStyle(Color.cfTertiaryLabel)
                    }
                }
            }
        }
        .chartXAxis {
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
        .frame(height: 140)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: .cfSpacing8) {
                Image(systemName: "chart.bar")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfTertiaryLabel)
                Text("No reading activity yet")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            Spacer()
        }
        .frame(height: 100)
    }

    // MARK: - Helpers

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private func isoDate(_ string: String) -> Date? {
        Self.dateParser.date(from: string)
    }

    private func dayLabel(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }
}

// MARK: - Audio Graph (AXChartDescriptorRepresentable)

extension ReadingTimeTrendChart: @preconcurrency AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let maxMinutes = points.max(by: { $0.minutes < $1.minutes })?.minutes ?? 60
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Day",
            categoryOrder: points.map { $0.label }
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Minutes read",
            range: 0...Double(max(maxMinutes, 1)),
            gridlinePositions: []
        ) { v in v.isFinite ? "\(Int(v)) min" : "" }
        let series = AXDataSeriesDescriptor(
            name: "Minutes read",
            isContinuous: false,
            dataPoints: points.map { point in
                AXDataPoint(x: point.label, y: Double(point.minutes))
            }
        )
        return AXChartDescriptor(
            title: "Daily Reading Time",
            summary: audioGraphSummary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Preview

#Preview("ReadingTimeTrendChart") {
    let days: [StreakDay] = [
        StreakDay(date: "2026-06-26", minutesRead: 0),
        StreakDay(date: "2026-06-27", minutesRead: 12),
        StreakDay(date: "2026-06-28", minutesRead: 25),
        StreakDay(date: "2026-06-29", minutesRead: 8),
        StreakDay(date: "2026-06-30", minutesRead: 30),
        StreakDay(date: "2026-07-01", minutesRead: 45),
        StreakDay(date: "2026-07-02", minutesRead: 15),
    ]
    ReadingTimeTrendChart(days: days)
        .padding(.cfSpacing16)
        .background(Color.cfGroupedBackground)
}
