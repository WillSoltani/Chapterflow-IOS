import SwiftUI
import Models
import DesignSystem
import CoreKit
import AIFeature
import Persistence

/// All books in a single category, reached by tapping a category on Discover.
///
/// Shows a searchable, sorted list using ``BookCardView`` rows and routes
/// taps into ``BookDetailView``.
public struct CategoryDetailView: View {

    let category: String
    let books: [BookCatalogItem]
    let savedBookIds: Set<String>
    let progressItems: [ProgressOverviewItem]
    let bookDetailRepository: any BookDetailRepository
    let aiRepository: (any AIRepository)?
    let preferences: AppPreferences
    let store: KeyValueStore
    let downloadManager: DownloadManager?
    let accountID: String?
    let isGuest: Bool
    let workPermit: SessionWorkPermit
    let onToggleSaved: (String) -> Void
    let onOpenReader: ((String, Int, VariantFamily) -> Void)?
    let onShowPaywall: (() -> Void)?
    let onSignInRequired: ((String, VariantFamily) -> Void)?

    @State private var searchQuery: String = ""
    @State private var router = Router()

    public init(
        category: String,
        books: [BookCatalogItem],
        savedBookIds: Set<String> = [],
        progressItems: [ProgressOverviewItem] = [],
        bookDetailRepository: any BookDetailRepository,
        aiRepository: (any AIRepository)? = nil,
        preferences: AppPreferences,
        store: KeyValueStore,
        downloadManager: DownloadManager? = nil,
        accountID: String? = nil,
        isGuest: Bool = false,
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        onToggleSaved: @escaping (String) -> Void,
        onOpenReader: ((String, Int, VariantFamily) -> Void)? = nil,
        onShowPaywall: (() -> Void)? = nil,
        onSignInRequired: ((String, VariantFamily) -> Void)? = nil
    ) {
        self.category = category
        self.books = books
        self.savedBookIds = savedBookIds
        self.progressItems = progressItems
        self.bookDetailRepository = bookDetailRepository
        self.aiRepository = aiRepository
        self.preferences = preferences
        self.store = store
        self.downloadManager = downloadManager
        self.accountID = accountID
        self.isGuest = isGuest
        self.workPermit = workPermit
        self.onToggleSaved = onToggleSaved
        self.onOpenReader = onOpenReader
        self.onShowPaywall = onShowPaywall
        self.onSignInRequired = onSignInRequired
    }

    // MARK: - Filtered

    private var filteredBooks: [BookCatalogItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return books }
        return books.filter {
            $0.title.lowercased().contains(q) ||
            $0.author.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack(path: $router.path) {
            Group {
                if filteredBooks.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else {
                    bookList
                }
            }
            .navigationTitle(category)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .searchable(text: $searchQuery, prompt: "Search in \(category)…")
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .bookDetail(let bookId):
                    BookDetailView(
                        bookId: bookId,
                        repository: bookDetailRepository,
                        aiRepository: aiRepository,
                        preferences: preferences,
                        store: store,
                        downloadManager: downloadManager,
                        accountID: accountID,
                        isGuest: isGuest,
                        workPermit: workPermit,
                        onOpenReader: onOpenReader,
                        onShowPaywall: onShowPaywall,
                        onSignInRequired: onSignInRequired
                    )
                case .globalSearch:
                    EmptyView()
                case .categoryDetail:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Book list

    private var bookList: some View {
        List {
            ForEach(filteredBooks) { book in
                BookCardView(
                    book: book,
                    progress: progressItem(for: book.bookId),
                    isSaved: savedBookIds.contains(book.bookId),
                    onSave: { onToggleSaved(book.bookId) },
                    onTap: { router.push(LibraryRoute.bookDetail(bookId: book.bookId)) }
                )
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: .cfSpacing16,
                    bottom: 0,
                    trailing: .cfSpacing16
                ))
                .listRowBackground(Color.cfBackground)
                .contextMenu {
                    contextMenu(for: book)
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: filteredBooks.map(\.bookId))
    }

    // MARK: - Helpers

    private func progressItem(for bookId: String) -> ProgressOverviewItem? {
        progressItems.first { $0.bookId == bookId }
    }

    @ViewBuilder
    private func contextMenu(for book: BookCatalogItem) -> some View {
        let saved = savedBookIds.contains(book.bookId)
        Button {
            onToggleSaved(book.bookId)
        } label: {
            Label(saved ? "Remove from Saved" : "Save",
                  systemImage: saved ? "bookmark.slash" : "bookmark")
        }
        Button {
            router.push(LibraryRoute.bookDetail(bookId: book.bookId))
        } label: {
            Label("Open Book", systemImage: "book")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Category detail — loaded") {
    CategoryDetailView(
        category: "Productivity",
        books: PreviewData.books,
        savedBookIds: ["b-deep-work"],
        progressItems: [PreviewData.atomicHabitsProgress],
        bookDetailRepository: PreviewData.bookDetailInProgress,
        preferences: AppPreferences(keyPrefix: "preview.category."),
        store: KeyValueStore(keyPrefix: "preview.category."),
        onToggleSaved: { _ in }
    )
}

#Preview("Category detail — dark mode") {
    CategoryDetailView(
        category: "Productivity",
        books: PreviewData.books,
        bookDetailRepository: PreviewData.bookDetailFreeLocked,
        preferences: AppPreferences(keyPrefix: "preview.category."),
        store: KeyValueStore(keyPrefix: "preview.category."),
        onToggleSaved: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Category detail — XXL text") {
    CategoryDetailView(
        category: "Psychology",
        books: PreviewData.books,
        bookDetailRepository: PreviewData.bookDetailFreeLocked,
        preferences: AppPreferences(keyPrefix: "preview.category."),
        store: KeyValueStore(keyPrefix: "preview.category."),
        onToggleSaved: { _ in }
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
