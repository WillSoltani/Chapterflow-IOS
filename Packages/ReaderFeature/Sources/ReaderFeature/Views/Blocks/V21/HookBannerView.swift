import SwiftUI
import DesignSystem

/// The v21 HOOK banner rendered at the very top of a chapter.
///
/// Visually distinct from the generic callout: larger serif type, a full-width
/// tinted surface, and a prominent left accent bar draw the reader in before the
/// narrative begins.
struct HookBannerView: View {
    let text: String

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(appearance.colors.accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: .cfSpacing12) {
                Label {
                    Text("HOOK")
                        .font(.cfCaption)
                        .foregroundStyle(appearance.colors.accent)
                        .kerning(1.2)
                } icon: {
                    Image(systemName: "sparkles")
                        .font(.cfCaption)
                        .foregroundStyle(appearance.colors.accent)
                }

                Text(AttributedString.inlineMarkdown(text))
                    .font(.system(size: hookFontSize, weight: .light, design: .serif))
                    .foregroundStyle(appearance.colors.primaryText)
                    .lineSpacing(appearance.lineSpacing + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.cfSpacing20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appearance.colors.accent.opacity(0.06))
        }
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius16))
        .padding(.vertical, .cfSpacing12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hook. \(text)")
    }

    @ScaledMetric(relativeTo: .title3) private var hookFontSize: CGFloat = 20
}
