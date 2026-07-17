import SwiftUI
import Models
import DesignSystem

/// A compact vertical card for the "Continue Reading" horizontal scroll rail.
///
/// Shows the book cover with an overlaid progress ring, the book title, and the
/// chapter the user is currently on.
public struct ContinueReadingCard: View {

    let book: BookCatalogItem
    let progress: ProgressOverviewItem
    let onTap: () -> Void

    public init(
        book: BookCatalogItem,
        progress: ProgressOverviewItem,
        onTap: @escaping () -> Void
    ) {
        self.book = book
        self.progress = progress
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                coverWithRing
                titleStack
            }
            .padding(.cfSpacing12)
            .frame(width: 148)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    private var coverWithRing: some View {
        ZStack(alignment: .bottomTrailing) {
            BookCoverView(cover: book.cover, coverImageURL: book.coverImageURL, size: 72)
            ProgressRingView(progress: progress.completionFraction, size: 26, lineWidth: 3)
                .background(
                    Circle().fill(Color.cfBackground).padding(-3)
                )
                .offset(x: 4, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: .cfSpacing2) {
            Text(book.title)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfLabel)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ch. \(progress.currentChapterNumber)")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
    }

    private var accessibilityLabel: String {
        "\(book.title), chapter \(progress.currentChapterNumber) of \(progress.totalChapters), " +
        "\(Int((progress.completionFraction * 100).rounded()))% complete"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Continue reading card", traits: .sizeThatFitsLayout) {
    HStack(spacing: 12) {
        ContinueReadingCard(
            book: PreviewData.atomicHabits,
            progress: PreviewData.atomicHabitsProgress,
            onTap: {}
        )
        ContinueReadingCard(
            book: PreviewData.deepWork,
            progress: PreviewData.deepWorkProgress,
            onTap: {}
        )
    }
    .padding()
}

#Preview("Dark mode", traits: .sizeThatFitsLayout) {
    ContinueReadingCard(
        book: PreviewData.atomicHabits,
        progress: PreviewData.atomicHabitsProgress,
        onTap: {}
    )
    .padding()
    .preferredColorScheme(.dark)
}
#endif
