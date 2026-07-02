import SwiftUI
import Models
import DesignSystem

/// Renders a book's emoji + gradient cover — no image download required.
///
/// The design is an emoji centred on a vertical gradient derived from the
/// `cover.color` hex string. Falls back to a neutral DesignSystem fill when
/// the cover data is absent or the hex cannot be parsed.
public struct BookCoverView: View {

    let cover: Cover?
    let size: CGFloat

    public init(cover: Cover?, size: CGFloat = 56) {
        self.cover = cover
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(gradient)
            Text(cover?.emoji ?? "📖")
                .font(.system(size: size * 0.45))
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size * coverAspect)
        .accessibilityHidden(true)
    }

    // MARK: - Derived

    private var cornerRadius: CGFloat {
        switch size {
        case ..<40: return .cfRadius8
        case 40..<80: return .cfRadius12
        default: return .cfRadius16
        }
    }

    private var coverAspect: CGFloat { 1.4 }

    private var gradient: LinearGradient {
        let base = parseHex(cover?.color) ?? Color.cfSecondaryFill
        return LinearGradient(
            colors: [base.opacity(0.95), base.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func parseHex(_ hex: String?) -> Color? {
        guard let hex else { return nil }
        let clean = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return nil }
        return Color(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Cover sizes", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        BookCoverView(cover: PreviewData.atomicHabits.cover, size: 40)
        BookCoverView(cover: PreviewData.deepWork.cover, size: 56)
        BookCoverView(cover: PreviewData.thinkingFastAndSlow.cover, size: 72)
        BookCoverView(cover: nil, size: 56)
    }
    .padding()
}

#Preview("Dark mode", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        BookCoverView(cover: PreviewData.atomicHabits.cover, size: 56)
        BookCoverView(cover: PreviewData.deepWork.cover, size: 56)
    }
    .padding()
    .preferredColorScheme(.dark)
}
#endif
