import SwiftUI
import DesignSystem

/// A shimmering placeholder that matches the shape of a ``BookCardView`` row.
///
/// Shown while the catalog or progress data is loading. The shimmer animation
/// respects Reduce Motion by becoming a static fill instead.
struct BookCardSkeleton: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: .cfSpacing12) {
            // Cover placeholder
            RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous)
                .fill(shimmerFill)
                .frame(width: 56, height: 78)

            VStack(alignment: .leading, spacing: .cfSpacing8) {
                // Title line
                RoundedRectangle(cornerRadius: .cfRadius4, style: .continuous)
                    .fill(shimmerFill)
                    .frame(height: 14)
                // Author line — shorter
                RoundedRectangle(cornerRadius: .cfRadius4, style: .continuous)
                    .fill(shimmerFill)
                    .frame(width: 100, height: 12)
                // Category pill
                RoundedRectangle(cornerRadius: .cfRadius4, style: .continuous)
                    .fill(shimmerFill)
                    .frame(width: 70, height: 10)
            }

            Spacer()
        }
        .padding(.vertical, .cfSpacing8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .linear(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) { phase = 1 }
        }
        .accessibilityLabel("Loading")
        .accessibilityHidden(true)
    }

    private var shimmerFill: some ShapeStyle {
        if reduceMotion {
            return AnyShapeStyle(Color.cfSecondaryFill)
        }
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: Color.cfSecondaryFill,          location: max(0, phase - 0.3)),
                    .init(color: Color.cfTertiaryBackground,     location: phase),
                    .init(color: Color.cfSecondaryFill,          location: min(1, phase + 0.3)),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

/// A column of `count` ``BookCardSkeleton`` rows, used as a loading placeholder.
public struct BookListSkeleton: View {
    let count: Int

    public init(count: Int = 5) {
        self.count = count
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                BookCardSkeleton()
                    .padding(.horizontal, .cfSpacing16)
                Divider().padding(.leading, 80)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Skeleton", traits: .sizeThatFitsLayout) {
    BookListSkeleton(count: 3)
        .padding(.vertical)
}
#endif
