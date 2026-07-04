import SwiftUI
import DesignSystem

/// An interactive scrubber for navigating within the current chapter.
///
/// Wraps `Slider` for full accessibility support. While dragging, the slider
/// thumb tracks the user's finger. On release, `onSeek(blockIndex:)` is called
/// with the target block index (clamped to the block array bounds).
///
/// The displayed value follows `readPercent` when idle and the drag position
/// while the user is interacting.
public struct ChapterScrubberView: View {
    public let readPercent: Double
    public let blockCount: Int
    public let onSeek: (Int) -> Void

    @State private var sliderValue: Double
    @State private var isDragging = false

    public init(readPercent: Double, blockCount: Int, onSeek: @escaping (Int) -> Void) {
        self.readPercent = readPercent
        self.blockCount = blockCount
        self.onSeek = onSeek
        _sliderValue = State(initialValue: readPercent)
    }

    public var body: some View {
        Slider(
            value: $sliderValue,
            in: 0...1,
            onEditingChanged: { editing in
                isDragging = editing
                if !editing {
                    let blockIndex = clampedBlock(from: sliderValue)
                    onSeek(blockIndex)
                }
            }
        )
        .tint(Color.cfAccent)
        .onChange(of: readPercent) { _, newValue in
            guard !isDragging else { return }
            sliderValue = newValue
        }
        .accessibilityLabel("Chapter position")
        .accessibilityValue("\(Int(readPercent * 100)) percent read")
    }

    private func clampedBlock(from percent: Double) -> Int {
        guard blockCount > 0 else { return 0 }
        let raw = Int((percent * Double(blockCount)).rounded())
        return max(0, min(blockCount - 1, raw))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Scrubber — light") {
    @Previewable @State var percent = 0.3
    VStack(spacing: .cfSpacing24) {
        Text("Position: \(Int(percent * 100))%")
            .font(.cfCaption)
            .foregroundStyle(Color.cfSecondaryLabel)
        ChapterScrubberView(
            readPercent: percent,
            blockCount: 40,
            onSeek: { block in
                percent = Double(block) / 40.0
            }
        )
        .padding(.horizontal, .cfSpacing16)
    }
    .padding()
}

#Preview("Scrubber — dark") {
    @Previewable @State var percent = 0.6
    ChapterScrubberView(
        readPercent: percent,
        blockCount: 40,
        onSeek: { _ in }
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Scrubber — XXL text") {
    ChapterScrubberView(readPercent: 0.5, blockCount: 40, onSeek: { _ in })
        .padding()
        .dynamicTypeSize(.accessibility3)
}
#endif
