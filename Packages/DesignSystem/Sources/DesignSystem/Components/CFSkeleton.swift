import SwiftUI

/// A pulsing placeholder shown while content is loading.
///
/// Respects Reduce Motion — when enabled the opacity is held at 0.6 (no pulse).
public struct CFSkeleton: View {
    private let shape: AnyShape

    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a skeleton with a `RoundedRectangle(cornerRadius: .cfRadius8)` shape.
    public init() {
        shape = AnyShape(RoundedRectangle(cornerRadius: .cfRadius8))
    }

    /// Creates a skeleton using the provided `shape`.
    public init<S: Shape>(_ shape: S) {
        self.shape = AnyShape(shape)
    }

    public var body: some View {
        shape
            .fill(Color.cfFill)
            .opacity(animating ? 0.35 : 0.7)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                ) {
                    animating = true
                }
            }
            .onDisappear {
                animating = false
            }
    }
}

// MARK: - Preview

#Preview("CFSkeleton") {
    VStack(alignment: .leading, spacing: .cfSpacing12) {
        CFSkeleton()
            .frame(height: 20)
            .frame(maxWidth: 200)
        CFSkeleton()
            .frame(height: 16)
            .frame(maxWidth: 280)
        CFSkeleton()
            .frame(height: 16)
            .frame(maxWidth: 240)
        HStack(spacing: .cfSpacing12) {
            CFSkeleton(Circle())
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                CFSkeleton().frame(height: 14).frame(maxWidth: 120)
                CFSkeleton().frame(height: 12).frame(maxWidth: 80)
            }
        }
    }
    .padding(.cfSpacing24)
}
