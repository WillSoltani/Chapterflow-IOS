import SwiftUI
import DesignSystem

/// Placeholder shown when a book is tapped — replaced by `ReaderFeature` once built.
public struct BookDetailPlaceholderView: View {
    let bookId: String

    public init(bookId: String) {
        self.bookId = bookId
    }

    public var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "book.closed",
            description: Text("The reader for this book is on its way.")
        )
        .navigationTitle("Book")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
