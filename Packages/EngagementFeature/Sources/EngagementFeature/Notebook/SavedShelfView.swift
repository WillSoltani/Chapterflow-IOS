import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - SavedShelfView

/// A scrollable grid shelf of saved books.
///
/// Shows the emoji+color cover for each saved book; tapping navigates to
/// the book's detail. The toggle is offered via swipe/long-press.
public struct SavedShelfView: View {

    private let model: SavedBooksModel
    private let onBookTap: (String) -> Void

    public init(model: SavedBooksModel, onBookTap: @escaping (String) -> Void) {
        self.model = model
        self.onBookTap = onBookTap
    }

    private let columns = [
        GridItem(.flexible(), spacing: .cfSpacing12),
        GridItem(.flexible(), spacing: .cfSpacing12),
        GridItem(.flexible(), spacing: .cfSpacing12),
    ]

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                savedSkeletonView
            case .loaded:
                if model.savedBooks.isEmpty {
                    emptyState
                } else {
                    loadedView
                }
            case .error(let error):
                errorView(error)
            }
        }
        .task { model.load() }
        .refreshable { await model.refresh() }
    }

    // MARK: - Loaded

    private var loadedView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: .cfSpacing12) {
                ForEach(model.savedBooks) { book in
                    SavedBookCard(
                        book: book,
                        onTap: { onBookTap(book.bookId) },
                        onRemove: {
                            Task { await model.toggleSaved(bookId: book.bookId) }
                        }
                    )
                }
            }
            .padding(.cfSpacing16)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.cfTertiaryLabel)
            Text("No Saved Books")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.cfLabel)
            Text("Books you save will appear here for quick access.")
                .font(.callout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .cfSpacing32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.cfSpacing48)
    }

    // MARK: - Error

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.cfSecondaryLabel)
            Text("Couldn't load saved books")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.cfSpacing32)
    }

    // MARK: - Skeleton

    private var savedSkeletonView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: .cfSpacing12) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .fill(Color.cfSecondaryBackground)
                        .aspectRatio(0.7, contentMode: .fit)
                        .shimmer()
                }
            }
            .padding(.cfSpacing16)
        }
    }
}

// MARK: - SavedBookCard

private struct SavedBookCard: View {

    let book: BookCatalogItem
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                coverView
                    .aspectRatio(0.7, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))

                VStack(alignment: .leading, spacing: .cfSpacing2) {
                    Text(book.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(2)

                    Text(book.author)
                        .font(.caption2)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove from Saved", systemImage: "bookmark.slash")
            }
        }
        .accessibilityLabel("\(book.title) by \(book.author), saved")
        .accessibilityHint("Tap to open, hold for options")
    }

    private var coverView: some View {
        ZStack {
            coverBackground
            if let emoji = book.cover?.emoji {
                Text(emoji)
                    .font(.system(size: 40))
            }
        }
    }

    private var coverBackground: some View {
        let color = coverColor
        return RoundedRectangle(cornerRadius: .cfRadius12)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var coverColor: Color {
        guard let hex = book.cover?.color else { return Color.cfAccent }
        return Color(hex: hex) ?? Color.cfAccent
    }
}

// MARK: - Color(hex:)

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard h.count == 6,
              let rgb = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Shimmer modifier

private extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.5)
        } else {
            content
                .overlay(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.3), .clear],
                        startPoint: .init(x: phase - 0.3, y: 0.5),
                        endPoint: .init(x: phase + 0.3, y: 0.5)
                    )
                    .allowsHitTesting(false)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview("Saved Shelf") {
    SavedShelfView(
        model: SavedBooksModel.preview,
        onBookTap: { _ in }
    )
    .background(Color.cfGroupedBackground)
}

#Preview("Saved Shelf Dark") {
    SavedShelfView(
        model: SavedBooksModel.preview,
        onBookTap: { _ in }
    )
    .background(Color.cfGroupedBackground)
    .preferredColorScheme(.dark)
}
