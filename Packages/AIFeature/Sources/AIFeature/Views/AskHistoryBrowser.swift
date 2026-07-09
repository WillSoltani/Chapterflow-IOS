import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// A browsable list of all Q&A threads the user has created across all books.
///
/// Each row shows the book title, last-updated timestamp, and question count.
/// Tapping a row opens ``AskThreadDetailView`` showing the full exchange.
public struct AskHistoryBrowser: View {
    private let userId: String
    private let buildModel: (String, String?) -> AskTheBookModel

    @Environment(\.modelContext) private var context
    @State private var threads: [CachedAskThread] = []
    @State private var searchText = ""

    public init(
        userId: String,
        buildModel: @escaping (String, String?) -> AskTheBookModel
    ) {
        self.userId = userId
        self.buildModel = buildModel
    }

    private var filteredThreads: [CachedAskThread] {
        guard !searchText.isEmpty else { return threads }
        return threads.filter {
            ($0.bookTitle ?? $0.bookId).localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        Group {
            if threads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .navigationTitle("Ask History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search books")
        .onAppear { reload() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Color.cfSecondaryLabel)
            Text("No past questions")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            Text("Your Q&A history will appear here\nafter you ask a question about a book.")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Thread list

    private var threadList: some View {
        List(filteredThreads, id: \.threadId) { thread in
            let model = buildModel(thread.bookId, thread.bookTitle)
            NavigationLink {
                AskThreadDetailView(model: model)
            } label: {
                threadRow(thread)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func threadRow(_ thread: CachedAskThread) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(thread.bookTitle ?? thread.bookId)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .lineLimit(1)

            HStack(spacing: .cfSpacing8) {
                Label("\(thread.messageCount) Q&As", systemImage: "bubble.left")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)

                Text("·")
                    .foregroundStyle(Color.cfTertiaryLabel)

                Text(thread.lastUpdatedAt, style: .relative)
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .fixedSize()
            }
        }
        .padding(.vertical, .cfSpacing4)
    }

    // MARK: - Helpers

    private func reload() {
        threads = AskThreadStore.allThreads(userId: userId, context: context)
    }
}

// MARK: - Thread detail view

/// Shows the full Q&A conversation for one book, with all history actions available.
public struct AskThreadDetailView: View {

    @State private var model: AskTheBookModel

    public init(model: AskTheBookModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        AskTheBookSheet(model: model)
    }
}
