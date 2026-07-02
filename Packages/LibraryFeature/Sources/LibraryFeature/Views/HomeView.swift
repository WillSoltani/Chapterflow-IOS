import SwiftUI
import Models
import DesignSystem
import CoreKit
#if canImport(UIKit)
import UIKit
#endif

/// The Home tab: Continue Reading rail, Your Library (saved books),
/// and Discover (catalog grouped by category).
public struct HomeView: View {

    @State private var model: HomeModel
    @State private var router = Router()

    private let bookDetailRepository: any BookDetailRepository
    private let onOpenReader: ((String, Int) -> Void)?
    private let onShowPaywall: (() -> Void)?

    public init(
        repository: any LibraryRepository,
        bookDetailRepository: any BookDetailRepository,
        onOpenReader: ((String, Int) -> Void)? = nil,
        onShowPaywall: (() -> Void)? = nil
    ) {
        _model = State(initialValue: HomeModel(repository: repository))
        self.bookDetailRepository = bookDetailRepository
        self.onOpenReader = onOpenReader
        self.onShowPaywall = onShowPaywall
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationTitle("Home")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .refreshable { await model.fetch() }
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .bookDetail(let bookId):
                        BookDetailView(
                            bookId: bookId,
                            repository: bookDetailRepository,
                            onOpenReader: onOpenReader,
                            onShowPaywall: onShowPaywall
                        )
                    }
                }
        }
        .task { await model.fetch() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle:
            BookListSkeleton()
                .padding(.top, .cfSpacing8)
        case .loading where model.books.isEmpty:
            BookListSkeleton()
                .padding(.top, .cfSpacing8)
        case .error(let msg):
            errorView(msg)
        default:
            loadedScrollView
        }
    }

    private var loadedScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .cfSpacing32) {
                if !model.continueReadingBooks.isEmpty {
                    continueReadingSection
                }
                if !model.savedBooks.isEmpty {
                    savedBooksSection
                }
                if !model.booksByCategory.isEmpty {
                    discoverSection
                }
            }
            .padding(.bottom, .cfSpacing32)
        }
    }

    // MARK: - Continue Reading

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            sectionHeader("Continue Reading")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: .cfSpacing12) {
                    ForEach(model.continueReadingBooks, id: \.book.bookId) { pair in
                        ContinueReadingCard(book: pair.book, progress: pair.progress) {
                            router.push(LibraryRoute.bookDetail(bookId: pair.book.bookId))
                        }
                    }
                }
                .padding(.horizontal, .cfSpacing16)
            }
        }
        .padding(.top, .cfSpacing16)
    }

    // MARK: - Your Library

    private var savedBooksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Your Library")
                .padding(.horizontal, .cfSpacing16)
            Divider().padding(.leading, .cfSpacing16)
            ForEach(model.savedBooks) { book in
                BookCardView(
                    book: book,
                    progress: progressItem(for: book.bookId),
                    isSaved: true,
                    onSave: { Task { await model.toggleSaved(bookId: book.bookId) } },
                    onTap: { router.push(LibraryRoute.bookDetail(bookId: book.bookId)) }
                )
                .padding(.horizontal, .cfSpacing16)
                .contextMenu {
                    savedContextMenu(for: book)
                }
                Divider().padding(.leading, 80)
            }
        }
    }

    // MARK: - Discover

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing24) {
            sectionHeader("Discover")
                .padding(.horizontal, .cfSpacing16)
            ForEach(model.booksByCategory, id: \.category) { group in
                categorySection(group.category, books: group.books)
            }
        }
    }

    private func categorySection(_ category: String, books: [BookCatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category)
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
                .padding(.horizontal, .cfSpacing16)
                .padding(.bottom, .cfSpacing8)
            Divider().padding(.leading, .cfSpacing16)
            ForEach(books) { book in
                BookCardView(
                    book: book,
                    isSaved: model.savedBookIds.contains(book.bookId),
                    onSave: { Task { await model.toggleSaved(bookId: book.bookId) } },
                    onTap: { router.push(LibraryRoute.bookDetail(bookId: book.bookId)) }
                )
                .padding(.horizontal, .cfSpacing16)
                .contextMenu { savedContextMenu(for: book) }
                Divider().padding(.leading, 80)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await model.fetch() } }
                .buttonStyle(.borderedProminent)
                .tint(.cfAccent)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.cfTitle2)
            .foregroundStyle(Color.cfLabel)
            .padding(.horizontal, .cfSpacing16)
    }

    private func progressItem(for bookId: String) -> ProgressOverviewItem? {
        model.progressItems.first { $0.bookId == bookId }
    }

    @ViewBuilder
    private func savedContextMenu(for book: BookCatalogItem) -> some View {
        let isSaved = model.savedBookIds.contains(book.bookId)
        Button {
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
            Task { await model.toggleSaved(bookId: book.bookId) }
        } label: {
            Label(isSaved ? "Remove from Saved" : "Save",
                  systemImage: isSaved ? "bookmark.slash" : "bookmark")
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
#Preview("Home — loaded") {
    HomeView(repository: PreviewData.loadedRepo, bookDetailRepository: PreviewData.bookDetailInProgress)
}

#Preview("Home — empty") {
    HomeView(repository: PreviewData.emptyRepo, bookDetailRepository: PreviewData.bookDetailFreeLocked)
}

#Preview("Home — error") {
    HomeView(repository: PreviewData.errorRepo, bookDetailRepository: PreviewData.bookDetailFreeLocked)
}

#Preview("Home — dark mode") {
    HomeView(repository: PreviewData.loadedRepo, bookDetailRepository: PreviewData.bookDetailInProgress)
        .preferredColorScheme(.dark)
}

#Preview("Home — XXL text") {
    HomeView(repository: PreviewData.loadedRepo, bookDetailRepository: PreviewData.bookDetailInProgress)
        .dynamicTypeSize(.accessibility3)
}
#endif
