import AppIntents
import WidgetKit
import SwiftUI

// MARK: - StartReadingControl

/// iOS 18 Control for "Start Reading" — appears in Control Center, Lock Screen,
/// and can be bound to the Action button. Backed by `StartReadingControlIntent`.
struct StartReadingControl: ControlWidget {
    static let kind = "com.chapterflow.ios.control.startReading"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { title in
            ControlWidgetButton(action: StartReadingControlIntent()) {
                Label(title, systemImage: "book.fill")
            }
            .tint(Color.cfWidgetAccent)
        }
        .displayName("Start Reading")
        .description("Open ChapterFlow at your current chapter.")
    }
}

extension StartReadingControl {
    struct Provider: ControlValueProvider {
        var previewValue: String { "Atomic Habits" }

        func currentValue() async throws -> String {
            WidgetSnapshot.load().continueBookTitle ?? "Start Reading"
        }
    }
}

// MARK: - StartReviewControl

/// iOS 18 Control for "Review Now" — shows the count of due cards and launches
/// ChapterFlow's spaced-repetition session.
struct StartReviewControl: ControlWidget {
    static let kind = "com.chapterflow.ios.control.startReview"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { count in
            ControlWidgetButton(action: StartReviewControlIntent()) {
                Label(
                    count > 0 ? "\(min(count, 99))\(count > 99 ? "+" : "") Due" : "Review Now",
                    systemImage: "brain.fill"
                )
            }
            .tint(Color.cfWidgetAccent)
        }
        .displayName("Review Now")
        .description("Open a spaced-repetition review session.")
    }
}

extension StartReviewControl {
    struct Provider: ControlValueProvider {
        var previewValue: Int { 7 }

        func currentValue() async throws -> Int {
            WidgetSnapshot.load().dueReviewCount
        }
    }
}

// MARK: - AudioPlaybackControl

/// iOS 18 Control toggle for audio narration play/pause.
/// Backed by `ToggleAudioControlIntent` which writes to the shared
/// `audioControlCommand` App Group key (consumed by AppModel on activation).
struct AudioPlaybackControl: ControlWidget {
    static let kind = "com.chapterflow.ios.control.audio"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isPlaying in
            ControlWidgetToggle(
                "Audio Narration",
                isOn: isPlaying,
                action: ToggleAudioControlIntent(),
                valueLabel: { on in
                    Label(
                        on ? "Playing" : "Paused",
                        systemImage: on ? "pause.fill" : "headphones"
                    )
                }
            )
            .tint(Color.cfWidgetAccent)
        }
        .displayName("Audio Narration")
        .description("Play or pause ChapterFlow's audio narration.")
    }
}

extension AudioPlaybackControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            let defaults = UserDefaults(suiteName: "group.com.chapterflow")
            return defaults?.bool(forKey: "controlIntent.isAudioPlaying") ?? false
        }
    }
}

// MARK: - Previews
// Control widgets render in the system Control Center UI which Xcode can't canvas-preview
// directly. The views below simulate the label content shown inside each control tile.

private struct ControlTile: View {
    let systemImage: String
    let title: String
    var isOn: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isOn ? Color.cfWidgetAccent : Color(.systemFill))
                    .frame(width: 56, height: 56)
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isOn ? .white : Color.cfWidgetAccent)
            }
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#Preview("Controls — Light") {
    HStack(spacing: 20) {
        ControlTile(systemImage: "book.fill", title: "Start Reading")
        ControlTile(systemImage: "brain.fill", title: "7 Due")
        ControlTile(systemImage: "headphones", title: "Paused")
        ControlTile(systemImage: "pause.fill", title: "Playing", isOn: true)
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}

#Preview("Controls — Dark") {
    HStack(spacing: 20) {
        ControlTile(systemImage: "book.fill", title: "Start Reading")
        ControlTile(systemImage: "brain.fill", title: "Review Now")
        ControlTile(systemImage: "headphones", title: "Paused")
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}

#Preview("Controls — XXL") {
    HStack(spacing: 20) {
        ControlTile(systemImage: "book.fill", title: "Start Reading")
        ControlTile(systemImage: "brain.fill", title: "99+ Due")
        ControlTile(systemImage: "pause.fill", title: "Playing", isOn: true)
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
    .dynamicTypeSize(.accessibility3)
}
