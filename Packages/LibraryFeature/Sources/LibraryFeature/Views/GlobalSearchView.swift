import SwiftUI
import Models
import DesignSystem
import CoreKit
import Persistence

/// Full-screen global search across book titles, authors, categories, tags,
/// and chapter titles. Reachable from both Home and Library via a toolbar button.
///
/// - Instant-as-you-type filtering with 300 ms debounce.
/// - Grouped results: Books / Chapters.
/// - Recent searches persisted to UserDefaults.
/// - Suggested categories derived from the index.
/// - Works offline over the cached search index.
public struct GlobalSearchView: View {

    @State private var model: SearchModel
    private let onOpenBook: (String) -> Void
    private let onOpenChapter: ((String, Int) -> Void)?

    public init(
        repository: any LibraryRepository,
        kvStore: KeyValueStore = KeyValueStore(),
        onOpenBook: @escaping (String) -> Void,
        onOpenChapter: ((String, Int) -> Void)? = nil
    ) {
        _model = State(initialValue: SearchModel(
            repository: repository,
            kvStore: kvStore
        ))
        self.onOpenBook = onOpenBook
        self.onOpenChapter = onOpenChapter
    }

    public var body: some View {
        content
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            #if os(iOS)
            .searchable(
                text: $model.rawQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Books, chapters, authors…"
            )
            #else
            .searchable(text: $model.rawQuery, prompt: "Books, chapters, authors…")
            #endif
            .searchSuggestions {
                suggestionsList
            }
            .onChange(of: model.rawQuery) {
                model.onQueryChanged()
            }
            .onSubmit(of: .search) {
                model.commitSearch(model.rawQuery)
            }
            .task { await model.fetch() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading where model.indexIsEmpty:
            loadingView
        case .error(let msg):
            errorView(msg)
        default:
            resultsList
        }
    }

    // MARK: - Results list

    private var resultsList: some View {
        List {
            if model.isSearching {
                searchResultSections
            } else {
                idleSections
            }
        }
        .listStyle(.plain)
        .animation(.default, value: model.bookResults.map(\.id))
        .animation(.default, value: model.chapterResults.map(\.id))
    }

    // MARK: - Idle state (no query)

    @ViewBuilder
    private var idleSections: some View {
        if !model.recentSearches.isEmpty {
            Section {
                ForEach(model.recentSearches, id: \.self) { term in
                    recentSearchRow(term)
                }
            } header: {
                sectionHeader("Recent") {
                    Button("Clear") { model.clearRecentSearches() }
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfAccent)
                }
            }
        }

        if !model.suggestedCategories.isEmpty {
            Section {
                suggestedChips
                    .listRowInsets(EdgeInsets(
                        top: .cfSpacing8, leading: .cfSpacing16,
                        bottom: .cfSpacing8, trailing: .cfSpacing16
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                sectionHeader("Browse by Topic") { EmptyView() }
            }
        }
    }

    private func recentSearchRow(_ term: String) -> some View {
        Button {
            model.applyQueryNow(term)
            model.commitSearch(term)
        } label: {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .frame(width: 20)
                Text(term)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                Spacer()
                Button {
                    model.removeRecentSearch(term)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.cfTertiaryLabel)
                        .font(.cfCaption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(term) from recent searches")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(term), recent search")
        .accessibilityHint("Double tap to search")
    }

    private var suggestedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .cfSpacing8) {
                ForEach(model.suggestedCategories, id: \.self) { category in
                    Button {
                        model.applyQueryNow(category)
                        model.commitSearch(category)
                    } label: {
                        Text(category)
                            .font(.cfCaption)
                            .padding(.horizontal, .cfSpacing12)
                            .padding(.vertical, .cfSpacing8)
                            .background(Capsule().fill(Color.cfSecondaryBackground))
                            .foregroundStyle(Color.cfLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Browse \(category)")
                }
            }
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResultSections: some View {
        if !model.hasResults {
            noResultsView
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        if !model.bookResults.isEmpty {
            Section {
                ForEach(model.bookResults) { result in
                    bookResultRow(result)
                }
            } header: {
                sectionHeader("Books") { EmptyView() }
            }
        }

        if !model.chapterResults.isEmpty {
            Section {
                ForEach(model.chapterResults) { result in
                    chapterResultRow(result)
                }
            } header: {
                sectionHeader("Chapters") { EmptyView() }
            }
        }
    }

    private func bookResultRow(_ result: SearchModel.BookResult) -> some View {
        Button {
            model.commitSearch(model.rawQuery)
            onOpenBook(result.book.bookId)
        } label: {
            HStack(spacing: .cfSpacing12) {
                miniCover(result.book)
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(result.book.title)
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(2)
                    Text(result.book.author)
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.cfCaption2)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
            .padding(.vertical, .cfSpacing4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.book.title) by \(result.book.author)")
        .accessibilityHint("Double tap to open book")
    }

    private func chapterResultRow(_ result: SearchModel.ChapterResult) -> some View {
        Button {
            model.commitSearch(model.rawQuery)
            if let onOpenChapter {
                onOpenChapter(result.book.bookId, result.chapter.number)
            } else {
                onOpenBook(result.book.bookId)
            }
        } label: {
            HStack(spacing: .cfSpacing12) {
                miniCover(result.book)
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(result.chapter.title)
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(2)
                    Text("\(result.book.title) · Ch. \(result.chapter.number)")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.cfCaption2)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
            .padding(.vertical, .cfSpacing4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.chapter.title), chapter \(result.chapter.number) of \(result.book.title)")
        .accessibilityHint("Double tap to open chapter")
    }

    // MARK: - Mini book cover

    private func miniCover(_ book: SearchIndexBook) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: .cfRadius8)
                .fill(coverBackground(book.cover?.color))
            if let emoji = book.cover?.emoji {
                Text(emoji)
                    .font(.system(size: 20))
            } else {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private func coverBackground(_ hex: String?) -> Color {
        guard let hex, hex.hasPrefix("#"), hex.count == 7,
              let r = Int(hex.dropFirst(1).prefix(2), radix: 16),
              let g = Int(hex.dropFirst(3).prefix(2), radix: 16),
              let b = Int(hex.dropFirst(5).prefix(2), radix: 16) else {
            return Color.cfSecondaryBackground
        }
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    // MARK: - Loading / empty / error

    private var loadingView: some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
            Text("Loading search index…")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, .cfSpacing64)
    }

    private var noResultsView: some View {
        ContentUnavailableView.search(text: model.rawQuery)
            .frame(maxWidth: .infinity)
            .padding(.top, .cfSpacing40)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Search Unavailable", systemImage: "magnifyingglass")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await model.fetch() } }
                .buttonStyle(.borderedProminent)
                .tint(.cfAccent)
        }
    }

    // MARK: - Search suggestions (shown below search bar)

    @ViewBuilder
    private var suggestionsList: some View {
        ForEach(model.recentSearches.prefix(5), id: \.self) { term in
            Label(term, systemImage: "clock")
                .searchCompletion(term)
        }
        if model.recentSearches.isEmpty {
            ForEach(model.suggestedCategories.prefix(5), id: \.self) { cat in
                Label(cat, systemImage: "magnifyingglass")
                    .searchCompletion(cat)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader<T: View>(
        _ title: String,
        @ViewBuilder trailing: () -> T
    ) -> some View {
        HStack {
            Text(title)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .textCase(.uppercase)
            Spacer()
            trailing()
        }
    }
}

// MARK: - SearchModel helper

private extension SearchModel {
    var indexIsEmpty: Bool { bookResults.isEmpty && chapterResults.isEmpty && suggestedCategories.isEmpty }
}

// MARK: - Previews

#if DEBUG
import Persistence

#Preview("Search — loaded, no query") {
    NavigationStack {
        GlobalSearchView(
            repository: SearchPreviewData.loadedRepo,
            kvStore: KeyValueStore(defaults: .init()),
            onOpenBook: { _ in },
            onOpenChapter: { _, _ in }
        )
    }
}

#Preview("Search — results for 'habit'") {
    NavigationStack {
        GlobalSearchView(
            repository: SearchPreviewData.loadedRepo,
            kvStore: KeyValueStore(defaults: .init()),
            onOpenBook: { _ in },
            onOpenChapter: { _, _ in }
        )
    }
}

#Preview("Search — dark mode") {
    NavigationStack {
        GlobalSearchView(
            repository: SearchPreviewData.loadedRepo,
            kvStore: KeyValueStore(defaults: .init()),
            onOpenBook: { _ in },
            onOpenChapter: { _, _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Search — XXL text") {
    NavigationStack {
        GlobalSearchView(
            repository: SearchPreviewData.loadedRepo,
            kvStore: KeyValueStore(defaults: .init()),
            onOpenBook: { _ in },
            onOpenChapter: { _, _ in }
        )
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Search — error / offline") {
    NavigationStack {
        GlobalSearchView(
            repository: SearchPreviewData.errorRepo,
            kvStore: KeyValueStore(defaults: .init()),
            onOpenBook: { _ in },
            onOpenChapter: { _, _ in }
        )
    }
}

enum SearchPreviewData {
    static let searchIndex = SearchIndexResponse(books: [
        SearchIndexBook(
            bookId: "b-atomic-habits",
            title: "Atomic Habits",
            author: "James Clear",
            categories: ["Productivity", "Psychology"],
            tags: ["habits", "behavior-change"],
            cover: Cover(emoji: "⚛️", color: "#2D6A4F"),
            chapters: [
                SearchIndexChapter(chapterId: "ch-ah-1", number: 1,
                                   title: "The Surprising Power of Atomic Habits"),
                SearchIndexChapter(chapterId: "ch-ah-2", number: 2,
                                   title: "How Your Habits Shape Your Identity"),
                SearchIndexChapter(chapterId: "ch-ah-3", number: 3,
                                   title: "How to Build Better Habits in 4 Simple Steps"),
            ]
        ),
        SearchIndexBook(
            bookId: "b-deep-work",
            title: "Deep Work",
            author: "Cal Newport",
            categories: ["Productivity", "Focus"],
            tags: ["focus", "deep-work"],
            cover: Cover(emoji: "🎯", color: "#1B4332"),
            chapters: [
                SearchIndexChapter(chapterId: "ch-dw-1", number: 1,
                                   title: "Deep Work Is Valuable"),
                SearchIndexChapter(chapterId: "ch-dw-2", number: 2,
                                   title: "Deep Work Is Rare"),
            ]
        ),
        SearchIndexBook(
            bookId: "b-thinking",
            title: "Thinking, Fast and Slow",
            author: "Daniel Kahneman",
            categories: ["Psychology", "Cognitive Science"],
            tags: ["cognitive-bias", "decision-making"],
            cover: Cover(emoji: "🧠", color: "#1A237E"),
            chapters: [
                SearchIndexChapter(chapterId: "ch-tfs-1", number: 1,
                                   title: "The Characters of the Story"),
                SearchIndexChapter(chapterId: "ch-tfs-2", number: 2,
                                   title: "Attention and Effort"),
            ]
        ),
    ])

    static var loadedRepo: FakeLibraryRepository {
        FakeLibraryRepository(
            catalog: [],
            searchIndex: searchIndex
        )
    }

    static var errorRepo: FakeLibraryRepository {
        FakeLibraryRepository(error: .offline)
    }
}
#endif
