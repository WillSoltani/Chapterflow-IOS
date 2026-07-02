import SwiftUI

/// A text view for primary reader prose that respects Dynamic Type as its floor
/// and multiplies by the user's font-scale preference on top.
///
/// `@ScaledMetric(relativeTo: .body)` captures the current Dynamic Type size.
/// The rendered size is `max(dtBase, dtBase × fontScale)`, so the reader
/// never renders text *below* the user's system accessibility setting.
struct ReaderBodyText: View {
    let text: AttributedString
    var alignment: TextAlignment = .leading

    @Environment(\.readerAppearance) private var appearance
    @ScaledMetric(relativeTo: .body) private var baseSize: CGFloat = 17

    private var fontSize: CGFloat {
        let scaled = baseSize * appearance.fontScale
        return max(baseSize, scaled)
    }

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .regular, design: .serif))
            .foregroundStyle(appearance.colors.primaryText)
            .lineSpacing(appearance.lineSpacing)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }
}

/// A serif pull-quote text view that scales with the user's font preference.
struct ReaderQuoteText: View {
    let text: AttributedString

    @Environment(\.readerAppearance) private var appearance
    @ScaledMetric(relativeTo: .title3) private var baseSize: CGFloat = 20

    private var fontSize: CGFloat {
        max(baseSize, baseSize * appearance.fontScale)
    }

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .light, design: .serif))
            .italic()
            .multilineTextAlignment(.center)
            .foregroundStyle(appearance.colors.quoteText)
            .lineSpacing(appearance.lineSpacing)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
