import SwiftUI

/// A shimmering placeholder for content that is still loading.
///
/// The shimmer sweep is disabled under Reduce Motion, falling back to a static
/// muted fill so loading states never animate for motion-sensitive users.
public struct Skeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = DSRadius.sm) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DSColor.separator)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        LinearGradient(
                            colors: [.clear, DSColor.surfaceElevated.opacity(0.55), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.6)
                        .offset(x: animating ? width : -width * 0.6)
                    }
                    .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("Skeleton", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Skeleton().frame(height: 20)
            Skeleton().frame(height: 20).padding(.trailing, DSSpacing.xl)
            Skeleton().frame(height: 20).padding(.trailing, DSSpacing.xxl)
        }
        .padding(DSSpacing.md)
    }
}
