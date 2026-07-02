import SwiftUI
import DesignSystem

/// A circular progress ring showing reading completion (0…1).
public struct ProgressRingView: View {

    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat

    public init(progress: Double, size: CGFloat = 28, lineWidth: CGFloat = 3) {
        self.progress = max(0, min(1, progress))
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.cfSecondaryFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.cfAccent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(progressLabel)
    }

    private var progressLabel: String {
        let pct = Int((progress * 100).rounded())
        return "\(pct)% complete"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Progress states", traits: .sizeThatFitsLayout) {
    HStack(spacing: 20) {
        ProgressRingView(progress: 0)
        ProgressRingView(progress: 0.25)
        ProgressRingView(progress: 0.5)
        ProgressRingView(progress: 0.75)
        ProgressRingView(progress: 1.0)
    }
    .padding()
}
#endif
