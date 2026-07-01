import SwiftUI

/// A rounded, elevated container for grouping content. The workhorse surface of
/// the app — token-driven padding, radius and shadow.
public struct Card<Content: View>: View {
    private let padding: CGFloat
    private let shadow: DSShadow
    private let content: Content

    public init(
        padding: CGFloat = DSSpacing.md,
        shadow: DSShadow = .card,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.shadow = shadow
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DSColor.surfaceElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            )
            .dsShadow(shadow)
    }
}

#Preview("Card", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("Atomic Habits")
                    .font(DSTypography.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Text("Chapter 3 · The 3rd Law")
                    .font(DSTypography.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(DSSpacing.md)
    }
}
