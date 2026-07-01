import SwiftUI

/// A rounded linear progress bar for reading progress and multi-step flows.
/// Animates fill changes, gated by Reduce Motion.
public struct LinearProgressBar: View {
    private let progress: Double
    private let height: CGFloat
    private let tint: Color

    public init(progress: Double, height: CGFloat = 6, tint: Color = DSColor.accent) {
        self.progress = progress
        self.height = height
        self.tint = tint
    }

    private var clamped: Double { min(max(progress, 0), 1) }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DSColor.separator)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clamped)
                    .dsAnimation(DSMotion.spring, value: clamped)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview("LinearProgressBar", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        VStack(spacing: DSSpacing.md) {
            LinearProgressBar(progress: 0.15)
            LinearProgressBar(progress: 0.5, height: 10)
            LinearProgressBar(progress: 0.9, tint: DSColor.success)
        }
        .padding(DSSpacing.md)
    }
}
