import SwiftUI
import DesignSystem

/// Renders a highlighted callout box for hooks, challenges, activations,
/// and other framing content.
struct CalloutBlockView: View {
    let title: String
    let bodyText: String

    @Environment(\.readerAppearance) private var appearance

    private var icon: String {
        switch title.lowercased() {
        case "hook": return "sparkles"
        case "counterintuition": return "arrow.triangle.2.circlepath"
        case "try this now": return "hand.raised.fill"
        case "24-hour challenge": return "clock.badge.checkmark"
        case "key takeaway": return "lightbulb.fill"
        case "common friction": return "exclamationmark.triangle"
        case "checkpoint": return "checkmark.circle.fill"
        case "activation": return "play.circle.fill"
        default: return "text.bubble"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Label {
                Text(title.uppercased())
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
                    .kerning(0.8)
            } icon: {
                Image(systemName: icon)
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
            }
            ReaderBodyText(text: AttributedString.inlineMarkdown(bodyText))
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(bodyText)")
    }
}
