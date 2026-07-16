import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Design tokens (mirrors DesignSystem; widget extensions can't import the package)
// Color(hexString:) is declared in WidgetDataReader.swift — only add the named constants here.

private extension Color {
    static let cfAccent = Color(red: 0.18, green: 0.40, blue: 0.82)
    static let cfFlame  = Color(red: 1.00, green: 0.45, blue: 0.15)
}

// MARK: - Lock Screen / Banner view

struct ReadingSessionLockScreenView: View {
    let context: ActivityViewContext<ReadingSessionAttributes>

    private var coverColor: Color {
        Color(hexString: context.attributes.bookColor) ?? .cfAccent.opacity(0.8)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Book cover thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(coverColor)
                    .frame(width: 52, height: 68)
                Text(context.attributes.bookEmoji)
                    .font(.system(size: 26))
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

            // Session info
            VStack(alignment: .leading, spacing: 4) {
                // Kind badge
                Label(
                    context.attributes.sessionKind == .audio ? "Listening" : "Reading",
                    systemImage: context.attributes.sessionKind == .audio
                        ? "headphones"
                        : "book.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.cfAccent)

                Text(context.attributes.bookTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Chapter \(context.attributes.chapterNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.cfAccent.opacity(0.15))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.cfAccent)
                            .frame(
                                width: geo.size.width * context.state.chapterProgress,
                                height: 4
                            )
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(context.state.elapsedString)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text("\(context.state.progressPercent)%")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .activityBackgroundTint(context.attributes.sessionKind == .audio
            ? Color.cfAccent.opacity(0.08)
            : Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }

}

// MARK: - Dynamic Island: Compact Leading

struct ReadingCompactLeadingView: View {
    let context: ActivityViewContext<ReadingSessionAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Text(context.attributes.bookEmoji)
                .font(.system(size: 14))
            // Mini progress ring
            ProgressView(value: context.state.chapterProgress)
                .progressViewStyle(.circular)
                .tint(.cfAccent)
                .frame(width: 16, height: 16)
        }
        .padding(.leading, 4)
    }
}

// MARK: - Dynamic Island: Compact Trailing

struct ReadingCompactTrailingView: View {
    let context: ActivityViewContext<ReadingSessionAttributes>

    var body: some View {
        HStack(spacing: 4) {
            if context.attributes.sessionKind == .audio {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.cfAccent)
                    .symbolEffect(.variableColor.iterative, isActive: context.state.isPlaying)
            }
            Text(context.state.elapsedString)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.trailing, 4)
    }
}

// MARK: - Dynamic Island: Minimal

struct ReadingMinimalView: View {
    let context: ActivityViewContext<ReadingSessionAttributes>

    var body: some View {
        Text(context.attributes.bookEmoji)
            .font(.system(size: 16))
    }
}

// MARK: - Dynamic Island: Expanded

struct ReadingExpandedView: View {
    let context: ActivityViewContext<ReadingSessionAttributes>

    private var coverColor: Color {
        Color(hexString: context.attributes.bookColor) ?? .cfAccent.opacity(0.8)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Leading region: cover + emoji
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(coverColor)
                        .frame(width: 36, height: 46)
                    Text(context.attributes.bookEmoji)
                        .font(.system(size: 20))
                }
            }
            .frame(maxWidth: .infinity)

            // Center region: book + chapter info
            VStack(alignment: .center, spacing: 2) {
                Text(context.attributes.bookTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Ch. \(context.attributes.chapterNumber) · \(context.state.progressPercent)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Progress bar
                ProgressView(value: context.state.chapterProgress)
                    .progressViewStyle(.linear)
                    .tint(.cfAccent)
                    .frame(maxWidth: 140)
            }
            .frame(maxWidth: .infinity)

            // Trailing region: elapsed time. Account-bound audio controls are
            // deferred until the Live Activity has explicit owner identity.
            VStack(spacing: 6) {
                Text(context.state.elapsedString)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
    }

}

// MARK: - ActivityConfiguration Widget

struct ReadingSessionActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingSessionAttributes.self) { context in
            ReadingSessionLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    Color(hexString: context.attributes.bookColor)
                                        ?? Color.cfAccent.opacity(0.8)
                                )
                                .frame(width: 32, height: 42)
                            Text(context.attributes.bookEmoji)
                                .font(.system(size: 18))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.state.elapsedString)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        if context.attributes.sessionKind == .audio {
                            Text(context.state.isPlaying ? "Playing" : "Paused")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        HStack {
                            Label(
                                context.attributes.sessionKind == .audio
                                    ? "Listening" : "Reading",
                                systemImage: context.attributes.sessionKind == .audio
                                    ? "headphones" : "book.fill"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.cfAccent)
                            Spacer()
                            Text("\(context.state.progressPercent)%")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: context.state.chapterProgress)
                            .progressViewStyle(.linear)
                            .tint(.cfAccent)
                    }
                    .padding(.horizontal, 2)
                }
            } compactLeading: {
                ReadingCompactLeadingView(context: context)
            } compactTrailing: {
                ReadingCompactTrailingView(context: context)
            } minimal: {
                ReadingMinimalView(context: context)
            }
            .contentMargins(.all, 0, for: .minimal)
            .widgetURL(URL(string: "chapterflow://live-activity/reading"))
        }
    }
}

// MARK: - Previews

#if DEBUG

private nonisolated(unsafe) let sampleReadingAttributes = ReadingSessionAttributes(
    bookTitle: "Atomic Habits",
    bookEmoji: "⚛️",
    bookColor: "#3A86FF",
    chapterNumber: 5,
    chapterTitle: "The Secret to Self-Control",
    sessionKind: .reading
)

private nonisolated(unsafe) let sampleAudioAttributes = ReadingSessionAttributes(
    bookTitle: "Thinking, Fast and Slow",
    bookEmoji: "🧠",
    bookColor: "#FF6B6B",
    chapterNumber: 3,
    chapterTitle: "The Lazy Controller",
    sessionKind: .audio
)

#Preview("Lock Screen — Reading", as: .content, using: sampleReadingAttributes) {
    ReadingSessionActivity()
} contentStates: {
    ReadingSessionStatus(elapsedSeconds: 754, chapterProgress: 0.62, isPlaying: false, streakAtRisk: false)
    ReadingSessionStatus(elapsedSeconds: 120, chapterProgress: 0.15, isPlaying: false, streakAtRisk: true)
}

#Preview("Lock Screen — Audio Playing", as: .content, using: sampleAudioAttributes) {
    ReadingSessionActivity()
} contentStates: {
    ReadingSessionStatus(elapsedSeconds: 423, chapterProgress: 0.38, isPlaying: true, streakAtRisk: false)
    ReadingSessionStatus(elapsedSeconds: 423, chapterProgress: 0.38, isPlaying: false, streakAtRisk: false)
}

#Preview("Dynamic Island Compact — Reading", as: .dynamicIsland(.compact), using: sampleReadingAttributes) {
    ReadingSessionActivity()
} contentStates: {
    ReadingSessionStatus(elapsedSeconds: 754, chapterProgress: 0.62, isPlaying: false, streakAtRisk: false)
}

#Preview("Dynamic Island Compact — Audio", as: .dynamicIsland(.compact), using: sampleAudioAttributes) {
    ReadingSessionActivity()
} contentStates: {
    ReadingSessionStatus(elapsedSeconds: 423, chapterProgress: 0.38, isPlaying: true, streakAtRisk: false)
}

#Preview("Dynamic Island Expanded — Reading", as: .dynamicIsland(.expanded), using: sampleReadingAttributes) {
    ReadingSessionActivity()
} contentStates: {
    ReadingSessionStatus(elapsedSeconds: 754, chapterProgress: 0.62, isPlaying: false, streakAtRisk: false)
}

#Preview("Dynamic Island Expanded — Audio", as: .dynamicIsland(.expanded), using: sampleAudioAttributes) {
    ReadingSessionActivity()
} contentStates: {
    ReadingSessionStatus(elapsedSeconds: 423, chapterProgress: 0.38, isPlaying: true, streakAtRisk: false)
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: sampleReadingAttributes) {
    ReadingSessionActivity()
} contentStates: {
    ReadingSessionStatus(elapsedSeconds: 754, chapterProgress: 0.62, isPlaying: false, streakAtRisk: false)
}

#endif
