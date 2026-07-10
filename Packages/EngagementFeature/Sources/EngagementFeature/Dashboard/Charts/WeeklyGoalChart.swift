import SwiftUI
import Charts
import Accessibility
import DesignSystem

/// A compact gauge showing weekly reading minutes vs the user's goal.
/// Data source: `Dashboard.weeklyReadMinutes` and `Dashboard.weeklyGoalMinutes`.
struct WeeklyGoalChart: View {
    let weeklyReadMinutes: Int
    let weeklyGoalMinutes: Int

    private var fraction: Double {
        guard weeklyGoalMinutes > 0 else { return 0 }
        return min(1.0, Double(weeklyReadMinutes) / Double(weeklyGoalMinutes))
    }

    private var isGoalMet: Bool { fraction >= 1.0 }

    var body: some View {
        HStack(spacing: .cfSpacing16) {
            gaugeView
            statsColumn
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Weekly goal: \(weeklyReadMinutes) of \(weeklyGoalMinutes) minutes read. " +
            "\(Int(fraction * 100)) percent complete."
        )
    }

    private var gaugeView: some View {
        Chart {
            // Background track
            SectorMark(
                angle: .value("Track", 1.0),
                innerRadius: .ratio(0.62),
                angularInset: 2
            )
            .foregroundStyle(Color.cfFill)
            .cornerRadius(4)
            .accessibilityHidden(true)

            // Progress arc
            if fraction > 0 {
                SectorMark(
                    angle: .value("Progress", fraction),
                    innerRadius: .ratio(0.62),
                    angularInset: 2
                )
                .foregroundStyle(
                    isGoalMet ? Color.green.gradient : Color.cfAccent.gradient
                )
                .cornerRadius(4)
                .accessibilityLabel("Weekly goal progress")
                .accessibilityValue("\(Int(fraction * 100)) percent of \(weeklyGoalMinutes) minutes")
            }
        }
        .accessibilityChartDescriptor(self)
        .frame(width: 100, height: 100)
        .overlay {
            VStack(spacing: 2) {
                Text("\(Int(fraction * 100))%")
                    .font(.cfHeadline)
                    .foregroundStyle(isGoalMet ? Color.green : Color.cfAccent)
                Text("done")
                    .font(.cfCaption2)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
    }

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This week")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Text("\(weeklyReadMinutes) min")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfLabel)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Text("\(weeklyGoalMinutes) min")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .monospacedDigit()
            }
            if isGoalMet {
                Label("Goal met!", systemImage: "checkmark.circle.fill")
                    .font(.cfCaption)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Audio Graph (AXChartDescriptorRepresentable)

extension WeeklyGoalChart: @preconcurrency AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Status",
            categoryOrder: ["Read", "Remaining"]
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Minutes",
            range: 0...Double(max(weeklyGoalMinutes, 1)),
            gridlinePositions: []
        ) { v in v.isFinite ? "\(Int(v)) min" : "" }
        let remaining = max(0, weeklyGoalMinutes - weeklyReadMinutes)
        let series = AXDataSeriesDescriptor(
            name: "Weekly reading goal",
            isContinuous: false,
            dataPoints: [
                AXDataPoint(x: "Read", y: Double(weeklyReadMinutes)),
                AXDataPoint(x: "Remaining", y: Double(remaining))
            ]
        )
        let summary = isGoalMet
            ? "Goal met. \(weeklyReadMinutes) of \(weeklyGoalMinutes) minutes read this week."
            : "\(weeklyReadMinutes) of \(weeklyGoalMinutes) minutes read. \(remaining) minutes remaining."
        return AXChartDescriptor(
            title: "Weekly Reading Goal",
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Preview

#Preview("WeeklyGoalChart") {
    VStack(spacing: .cfSpacing16) {
        WeeklyGoalChart(weeklyReadMinutes: 85, weeklyGoalMinutes: 120)
        Divider()
        WeeklyGoalChart(weeklyReadMinutes: 120, weeklyGoalMinutes: 120)
        Divider()
        WeeklyGoalChart(weeklyReadMinutes: 0, weeklyGoalMinutes: 60)
    }
    .padding(.cfSpacing16)
    .background(Color.cfGroupedBackground)
}
