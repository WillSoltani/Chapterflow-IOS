import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Streak-at-Risk Live Activity
//
// An evening countdown shown when the user's reading streak is about to reset
// at midnight. The activity ends when the user reads (markStreakSaved) or at
// midnight (dismissAtMidnight) via StreakAtRiskActivityManager.

// MARK: - Lock Screen / Banner

struct StreakAtRiskLockScreenView: View {
    let context: ActivityViewContext<StreakAtRiskAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Flame icon
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.45, blue: 0.15).opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "flame.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.15))
            }

            VStack(alignment: .leading, spacing: 4) {
                if context.state.isStreakSaved {
                    Label("Streak saved! 🎉", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text("Keep your streak alive!")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text("\(context.attributes.streakDays)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.15))
                        Text(context.attributes.streakDays == 1 ? "day streak" : "days streak")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(timerText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !context.state.isStreakSaved {
                Text(timerDate, style: .timer)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 1.0, green: 0.45, blue: 0.15).opacity(0.06))
    }

    private var timerDate: Date { context.state.midnightDeadline }
    private var timerText: String { "Resets at midnight" }
}

// MARK: - Dynamic Island: Compact Leading

struct StreakCompactLeadingView: View {
    let context: ActivityViewContext<StreakAtRiskAttributes>

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.15))
            Text("\(context.attributes.streakDays)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .padding(.leading, 4)
    }
}

// MARK: - Dynamic Island: Compact Trailing

struct StreakCompactTrailingView: View {
    let context: ActivityViewContext<StreakAtRiskAttributes>

    var body: some View {
        if context.state.isStreakSaved {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.trailing, 4)
        } else {
            Text(context.state.midnightDeadline, style: .timer)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.orange)
                .padding(.trailing, 4)
        }
    }
}

// MARK: - Dynamic Island: Minimal

struct StreakMinimalView: View {
    let context: ActivityViewContext<StreakAtRiskAttributes>

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.15))
    }
}

// MARK: - Dynamic Island: Expanded

struct StreakExpandedView: View {
    let context: ActivityViewContext<StreakAtRiskAttributes>

    var body: some View {
        if context.state.isStreakSaved {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak saved!")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(context.attributes.streakDays) days and counting")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
        } else {
            HStack {
                // Leading: flame + streak count
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.15))
                    Text("\(context.attributes.streakDays)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)

                // Center: label
                VStack(spacing: 2) {
                    Text("Keep your streak!")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Resets at midnight")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                // Trailing: countdown
                VStack(spacing: 2) {
                    Text("Time left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(context.state.midnightDeadline, style: .timer)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - ActivityConfiguration Widget

struct StreakAtRiskActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreakAtRiskAttributes.self) { context in
            StreakAtRiskLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.15))
                        Text("\(context.attributes.streakDays)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.isStreakSaved {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(context.state.midnightDeadline, style: .timer)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isStreakSaved
                         ? "Streak saved! Great job today."
                         : "Open ChapterFlow and read to keep your streak.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } compactLeading: {
                StreakCompactLeadingView(context: context)
            } compactTrailing: {
                StreakCompactTrailingView(context: context)
            } minimal: {
                StreakMinimalView(context: context)
            }
            .widgetURL(URL(string: "chapterflow://streak"))
        }
    }
}

// MARK: - Previews

#if DEBUG

private nonisolated(unsafe) let sampleStreakAttributes = StreakAtRiskAttributes(streakDays: 12)

private func midnight() -> Date {
    Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
}

#Preview("Streak At Risk — Lock Screen", as: .content, using: sampleStreakAttributes) {
    StreakAtRiskActivity()
} contentStates: {
    StreakAtRiskStatus(midnightDeadline: midnight(), isStreakSaved: false)
    StreakAtRiskStatus(midnightDeadline: midnight(), isStreakSaved: true)
}

#Preview("Streak At Risk — Compact", as: .dynamicIsland(.compact), using: sampleStreakAttributes) {
    StreakAtRiskActivity()
} contentStates: {
    StreakAtRiskStatus(midnightDeadline: midnight(), isStreakSaved: false)
}

#Preview("Streak At Risk — Expanded", as: .dynamicIsland(.expanded), using: sampleStreakAttributes) {
    StreakAtRiskActivity()
} contentStates: {
    StreakAtRiskStatus(midnightDeadline: midnight(), isStreakSaved: false)
    StreakAtRiskStatus(midnightDeadline: midnight(), isStreakSaved: true)
}

#endif
