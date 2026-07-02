import SwiftUI
import DesignSystem

/// The v21 "TRY THIS NOW" directive block.
///
/// An action-oriented card that invites immediate application. Uses a filled
/// accent header to clearly signal this is an actionable step, not prose.
struct TryThisNowView: View {
    let text: String

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "hand.raised.fill")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
                Text("TRY THIS NOW")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
                    .kerning(1.0)
                Spacer()
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing12)
            .background(appearance.colors.accent.opacity(0.10))

            ReaderBodyText(text: AttributedString.inlineMarkdown(text))
                .padding(.cfSpacing16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .overlay {
            RoundedRectangle(cornerRadius: .cfRadius12)
                .strokeBorder(appearance.colors.accent.opacity(0.25), lineWidth: 1)
        }
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Try this now. \(text)")
    }
}
