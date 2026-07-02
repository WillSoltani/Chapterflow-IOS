import SwiftUI
import DesignSystem

/// Renders a section heading or the top-level chapter title.
struct HeadingBlockView: View {
    let text: String
    let isChapterTitle: Bool

    var body: some View {
        Text(text)
            .font(isChapterTitle ? .cfTitle1 : .cfTitle3)
            .foregroundStyle(Color.cfLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isChapterTitle ? .cfSpacing32 : .cfSpacing24)
            .padding(.bottom, .cfSpacing8)
            .accessibilityAddTraits(.isHeader)
    }
}
