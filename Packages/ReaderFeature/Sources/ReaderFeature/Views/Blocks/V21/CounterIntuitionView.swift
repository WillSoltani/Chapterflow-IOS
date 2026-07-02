import SwiftUI
import DesignSystem

/// The v21 COUNTERINTUITION callout — the "twist" that reframes the reader's assumptions.
///
/// Styled with a rotation icon and a subtly differentiated surface to signal
/// that this content challenges conventional thinking.
struct CounterIntuitionView: View {
    let text: String

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label {
                Text("COUNTERINTUITION")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
                    .kerning(0.8)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
            }

            ReaderBodyText(text: AttributedString.inlineMarkdown(text))
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.colors.surfaceBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(appearance.colors.accent.opacity(0.30))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Counterintuition. \(text)")
    }
}
