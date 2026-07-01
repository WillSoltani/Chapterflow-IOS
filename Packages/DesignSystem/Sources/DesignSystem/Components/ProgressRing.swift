import SwiftUI

/// A circular progress ring for streaks, chapter completion and dashboards.
/// Animates fill changes (gated by Reduce Motion) and can show an optional
/// centered label.
public struct ProgressRing: View {
    private let progress: Double
    private let lineWidth: CGFloat
    private let diameter: CGFloat
    private let tint: Color
    private let label: LocalizedStringKey?

    public init(
        progress: Double,
        lineWidth: CGFloat = 8,
        diameter: CGFloat = 64,
        tint: Color = DSColor.accent,
        label: LocalizedStringKey? = nil
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.diameter = diameter
        self.tint = tint
        self.label = label
    }

    private var clamped: Double { min(max(progress, 0), 1) }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(DSColor.separator, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .dsAnimation(DSMotion.spring, value: clamped)
            if let label {
                Text(label)
                    .font(DSTypography.scaledFont(.footnote, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview("ProgressRing", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        HStack(spacing: DSSpacing.md) {
            ProgressRing(progress: 0.25, label: "25%")
            ProgressRing(progress: 0.6, tint: DSColor.success, label: "6/10")
            ProgressRing(progress: 1.0, tint: DSColor.success, label: "✓")
        }
        .padding(DSSpacing.md)
    }
}
