import SwiftUI
import DesignSystem

/// A seek bar for the audio player: a scrubber track with elapsed time and
/// remaining time labels.
///
/// - The user drags to scrub; `onSeek` fires with the new absolute position.
/// - Call sites own `currentTime` and `duration`; this view is fully controlled.
public struct AudioTimeline: View {

    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var scrubPosition: Double = 0

    public init(currentTime: Double, duration: Double, onSeek: @escaping (Double) -> Void) {
        self.currentTime = currentTime
        self.duration = duration
        self.onSeek = onSeek
    }

    private var displayTime: Double { isDragging ? scrubPosition : currentTime }

    public var body: some View {
        VStack(spacing: .cfSpacing8) {
            scrubber
            timeLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(timeString(displayTime))
        .accessibilityAdjustableAction { direction in
            let delta: Double = direction == .increment ? 15 : -15
            onSeek(max(0, min(displayTime + delta, duration)))
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = duration > 0 ? displayTime / duration : 0
            let clampedProgress = max(0, min(progress, 1))

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.cfSecondaryFill)
                    .frame(height: isDragging ? 6 : 4)

                // Fill
                Capsule()
                    .fill(Color.cfAccent)
                    .frame(width: clampedProgress * width, height: isDragging ? 6 : 4)

                // Thumb
                if isDragging {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
                        .frame(width: 22, height: 22)
                        .offset(x: clampedProgress * width - 11)
                }
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let ratio = max(0, min(value.location.x / width, 1))
                        scrubPosition = ratio * duration
                    }
                    .onEnded { value in
                        let ratio = max(0, min(value.location.x / width, 1))
                        let seekTime = ratio * duration
                        scrubPosition = seekTime
                        isDragging = false
                        onSeek(seekTime)
                    }
            )
        }
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    // MARK: - Time labels

    private var timeLabels: some View {
        HStack {
            Text(timeString(displayTime))
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .monospacedDigit()

            Spacer()

            Text("-\(timeString(max(0, duration - displayTime)))")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .monospacedDigit()
        }
    }

    // MARK: - Helpers

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var accessibilityLabel: String { "Seek bar" }
}

// MARK: - Preview

#if DEBUG
#Preview("Audio Timeline", traits: .sizeThatFitsLayout) {
    AudioTimeline(currentTime: 73, duration: 312, onSeek: { _ in })
        .padding(.horizontal, .cfSpacing24)
        .padding(.vertical, .cfSpacing16)
}
#endif
