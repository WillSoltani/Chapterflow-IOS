import SwiftUI
import Models
import DesignSystem
import CoreKit
import AIFeature
import Persistence
#if canImport(UIKit)
import UIKit
#endif

/// The Home tab: Continue Reading rail, Your Library (saved books),
/// and Discover (catalog grouped by category).
public struct HomeView: View {

    @State private var model: HomeModel
    @State private var router = Router()

    private let repository: any LibraryRepository
    private let bookDetailRepository: any BookDetailRepository
    private let aiRepository: (any AIRepository)?
    private let preferences: AppPreferences
    private let store: KeyValueStore
    private let downloadManager: DownloadManager?
    private let accountID: String?
    private let isGuest: Bool
    private let analytics: any AnalyticsClient
    private let workPermit: SessionWorkPermit
    private let onOpenReader: ((String, Int, VariantFamily) -> Void)?
    private let onShowPaywall: (() -> Void)?
    /// Called when a guest taps a gated action (save, etc.). Triggers the auth gate.
    private let onRequireAuth: (() -> Void)?
    /// Called when a guest taps "Sign in to Read" on a book detail screen.
    private let onSignInRequired: ((String, VariantFamily) -> Void)?
    /// Called when the user taps the bell icon to open the notification inbox.
    private let onShowNotificationInbox: (() -> Void)?

    public init(
        repository: any LibraryRepository,
        bookDetailRepository: any BookDetailRepository,
        aiRepository: (any AIRepository)? = nil,
        preferences: AppPreferences,
        store: KeyValueStore,
        downloadManager: DownloadManager? = nil,
        accountID: String? = nil,
        isGuest: Bool = false,
        analytics: any AnalyticsClient = NoopAnalyticsClient(),
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        onOpenReader: ((String, Int, VariantFamily) -> Void)? = nil,
        onShowPaywall: (() -> Void)? = nil,
        onRequireAuth: (() -> Void)? = nil,
        onSignInRequired: ((String, VariantFamily) -> Void)? = nil,
        onShowNotificationInbox: (() -> Void)? = nil
    ) {
        _model = State(initialValue: HomeModel(repository: repository))
        self.repository = repository
        self.bookDetailRepository = bookDetailRepository
        self.aiRepository = aiRepository
        self.preferences = preferences
        self.store = store
        self.downloadManager = downloadManager
        self.accountID = accountID
        self.isGuest = isGuest
        self.analytics = analytics
        self.workPermit = workPermit
        self.onOpenReader = onOpenReader
        self.onShowPaywall = onShowPaywall
        self.onRequireAuth = onRequireAuth
        self.onSignInRequired = onSignInRequired
        self.onShowNotificationInbox = onShowNotificationInbox
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationTitle("Home")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .refreshable { await model.fetch() }
                .toolbar { searchToolbarItem }
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
                            analytics: analytics,
                            workPermit: workPermit,
                            onOpenReader: onOpenReader,
                            onShowPaywall: onShowPaywall,
                            onSignInRequired: onSignInRequired
                        )
                    case .globalSearch:
                        GlobalSearchView(
                            repository: repository,
                            kvStore: store,
                            onOpenBook: { bookId in
                                router.push(LibraryRoute.bookDetail(bookId: bookId))
                            },
                            onOpenChapter: { bookId, _ in
                                router.push(LibraryRoute.bookDetail(bookId: bookId))
                            }
                        )
                    case .categoryDetail(let category):
                        CategoryDetailView(
                            category: category,
                            books: model.books.filter { $0.categories.contains(category) },
                            savedBookIds: model.savedBookIds,
                            progressItems: model.progressItems,
                            bookDetailRepository: bookDetailRepository,
                            aiRepository: aiRepository,
                            preferences: preferences,
                            store: store,
                            downloadManager: downloadManager,
                            accountID: accountID,
                            isGuest: isGuest,
                            workPermit: workPermit,
                            onToggleSaved: { bookId in
                                guard !isGuest else { onRequireAuth?(); return }
                                Task { await model.toggleSaved(bookId: bookId) }
                            },
                            onOpenReader: onOpenReader,
                            onShowPaywall: onShowPaywall,
                            onSignInRequired: onSignInRequired
                        )
                    }
                }
        }
        .task { await model.fetch() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var searchToolbarItem: some ToolbarContent {
        #if os(iOS)
        if let onShowNotificationInbox {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onShowNotificationInbox()
                } label: {
                    Image(systemName: "bell")
                        .accessibilityLabel("Open notification inbox")
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                router.push(LibraryRoute.globalSearch)
            } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel("Search books and chapters")
            }
        }
        #else
        ToolbarItem(placement: .automatic) {
            Button {
                router.push(LibraryRoute.globalSearch)
            } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel("Search books and chapters")
            }
        }
        #endif
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
                    onSave: {
                        guard !isGuest else { onRequireAuth?(); return }
                        Task { await model.toggleSaved(bookId: book.bookId) }
                    },
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
                    onSave: {
                        guard !isGuest else { onRequireAuth?(); return }
                        Task { await model.toggleSaved(bookId: book.bookId) }
                    },
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
    HomeView(
        repository: PreviewData.loadedRepo,
        bookDetailRepository: PreviewData.bookDetailInProgress,
        preferences: AppPreferences(keyPrefix: "preview.home."),
        store: KeyValueStore(keyPrefix: "preview.home.")
    )
}

#Preview("Home — empty") {
    HomeView(
        repository: PreviewData.emptyRepo,
        bookDetailRepository: PreviewData.bookDetailFreeLocked,
        preferences: AppPreferences(keyPrefix: "preview.home."),
        store: KeyValueStore(keyPrefix: "preview.home.")
    )
}

#Preview("Home — error") {
    HomeView(
        repository: PreviewData.errorRepo,
        bookDetailRepository: PreviewData.bookDetailFreeLocked,
        preferences: AppPreferences(keyPrefix: "preview.home."),
        store: KeyValueStore(keyPrefix: "preview.home.")
    )
}

#Preview("Home — dark mode") {
    HomeView(
        repository: PreviewData.loadedRepo,
        bookDetailRepository: PreviewData.bookDetailInProgress,
        preferences: AppPreferences(keyPrefix: "preview.home."),
        store: KeyValueStore(keyPrefix: "preview.home.")
    )
        .preferredColorScheme(.dark)
}

#Preview("Home — XXL text") {
    HomeView(
        repository: PreviewData.loadedRepo,
        bookDetailRepository: PreviewData.bookDetailInProgress,
        preferences: AppPreferences(keyPrefix: "preview.home."),
        store: KeyValueStore(keyPrefix: "preview.home.")
    )
        .dynamicTypeSize(.accessibility3)
}
#endif
