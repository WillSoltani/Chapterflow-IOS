import SwiftUI
import DesignSystem

/// A tappable chip representing one cited chapter number.
///
/// Tapping it calls the provided `action` closure (typically jumping the reader
/// to that chapter). Uses an accent-tinted pill shape per DesignSystem tokens.
struct CitationChipView: View {
    let chapterNumber: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "book.pages")
                    .font(.system(size: 11, weight: .medium))
                Text("Ch. \(chapterNumber)")
                    .font(.cfCaption)
            }
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, .cfSpacing4)
            .background(
                Capsule()
                    .fill(Color.cfAccent.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.cfAccent.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(Color.cfAccent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to chapter \(chapterNumber)")
        .accessibilityHint("Opens this chapter in the reader")
    }
}

#if DEBUG
#Preview("Citation chips — light") {
    HStack(spacing: .cfSpacing8) {
        CitationChipView(chapterNumber: 1) {}
        CitationChipView(chapterNumber: 4) {}
        CitationChipView(chapterNumber: 12) {}
    }
    .padding(.cfSpacing16)
}

#Preview("Citation chips — dark") {
    HStack(spacing: .cfSpacing8) {
        CitationChipView(chapterNumber: 1) {}
        CitationChipView(chapterNumber: 4) {}
    }
    .padding(.cfSpacing16)
    .preferredColorScheme(.dark)
}
#endif
