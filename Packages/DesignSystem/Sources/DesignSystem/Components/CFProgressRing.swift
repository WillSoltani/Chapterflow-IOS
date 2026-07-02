import SwiftUI

/// A circular progress indicator using the brand accent colour.
///
/// `progress` is clamped to `0…1`. The ring animates with a spring when
/// `progress` changes. Pair with `@Environment(\.accessibilityReduceMotion)`
/// in a parent if you need to gate animation externally.
public struct CFProgressRing: View {
    private let progress: Double
    private let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - progress: Completion fraction in `0…1`.
    ///   - lineWidth: Stroke width in points (default 6).
    public init(progress: Double, lineWidth: CGFloat = 6) {
        self.progress = max(0, min(1, progress))
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.cfAccent.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.cfAccent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75),
                    value: progress
                )
        }
    }
}

// MARK: - Preview

#Preview("CFProgressRing") {
    HStack(spacing: .cfSpacing24) {
        CFProgressRing(progress: 0.0)
            .frame(width: 48, height: 48)
        CFProgressRing(progress: 0.33)
            .frame(width: 48, height: 48)
        CFProgressRing(progress: 0.72)
            .frame(width: 48, height: 48)
        CFProgressRing(progress: 1.0)
            .frame(width: 48, height: 48)
    }
    .padding(.cfSpacing24)
}

#Preview("CFProgressRing animated") {
    @Previewable @State var progress: Double = 0.0
    VStack(spacing: .cfSpacing16) {
        CFProgressRing(progress: progress, lineWidth: 10)
            .frame(width: 80, height: 80)
        Slider(value: $progress)
            .padding(.horizontal, .cfSpacing24)
    }
    .padding(.cfSpacing24)
}
