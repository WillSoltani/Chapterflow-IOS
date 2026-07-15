import SwiftUI
import Models
import DesignSystem
import CoreKit
import AIFeature
import Persistence
#if canImport(UIKit)
import UIKit
#endif

/// The Discover tab: curated shelves, "For You", Journeys / Events entry points,
/// and a full category browser — all routing into ``BookDetailView``.
///
/// Journeys and Events are future features; pass closures from AppFeature when
/// those screens are ready (P5.6 / P5.7). Until then the banners are displayed
/// but the closures may be nil (tapping is a no-op).
public struct DiscoverView: View {

    @State private var model: DiscoverModel
    @State private var router = Router()

    private let bookDetailRepository: any BookDetailRepository
    private let aiRepository: (any AIRepository)?
    private let preferences: AppPreferences
    private let store: KeyValueStore
    private let downloadManager: DownloadManager?
    private let accountID: String?
    private let workPermit: SessionWorkPermit
    private let onOpenReader: ((String, Int, VariantFamily) -> Void)?
    private let onShowPaywall: (() -> Void)?
    private let onShowJourneys: (() -> Void)?
    private let onShowEvents: (() -> Void)?

    public init(
        repository: any LibraryRepository,
        bookDetailRepository: any BookDetailRepository,
        aiRepository: (any AIRepository)? = nil,
        preferences: AppPreferences,
        store: KeyValueStore,
        downloadManager: DownloadManager? = nil,
        accountID: String? = nil,
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        userInterests: [String] = [],
        onOpenReader: ((String, Int, VariantFamily) -> Void)? = nil,
        onShowPaywall: (() -> Void)? = nil,
        onShowJourneys: (() -> Void)? = nil,
        onShowEvents: (() -> Void)? = nil
    ) {
        _model = State(initialValue: DiscoverModel(
            repository: repository,
            userInterests: userInterests
        ))
        self.bookDetailRepository = bookDetailRepository
        self.aiRepository = aiRepository
        self.preferences = preferences
        self.store = store
        self.downloadManager = downloadManager
        self.accountID = accountID
        self.workPermit = workPermit
        self.onOpenReader = onOpenReader
        self.onShowPaywall = onShowPaywall
        self.onShowJourneys = onShowJourneys
        self.onShowEvents = onShowEvents
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationTitle("Discover")
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
                            aiRepository: aiRepository,
                            preferences: preferences,
                            store: store,
                            downloadManager: downloadManager,
                            accountID: accountID,
                            workPermit: workPermit,
                            onOpenReader: onOpenReader,
                            onShowPaywall: onShowPaywall
                        )
                    case .globalSearch:
                        EmptyView()
                    case .categoryDetail(let category):
                        categoryDetailView(for: category)
                    }
                }
        }
        .task { await model.fetch() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading where model.books.isEmpty:
            discoverSkeleton
        case .error(let msg):
            errorView(msg)
        default:
            loadedScrollView
        }
    }

    private var loadedScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .cfSpacing32) {

                // "For You" shelf — only shown when interests are set or there's data
                if !model.forYouBooks.isEmpty {
                    BookShelfView(
                        title: "For You",
                        books: model.forYouBooks,
                        savedBookIds: model.savedBookIds,
                        onToggleSaved: toggleSaved(_:),
                        onBookTapped: pushBook(_:)
                    )
                }

                // New & Updated shelf
                if !model.newBooks.isEmpty {
                    BookShelfView(
                        title: "New & Updated",
                        books: model.newBooks,
                        savedBookIds: model.savedBookIds,
                        onSeeAll: { router.push(LibraryRoute.categoryDetail(category: "_new")) },
                        onToggleSaved: toggleSaved(_:),
                        onBookTapped: pushBook(_:)
                    )
                }

                // Popular shelf
                if !model.popularBooks.isEmpty {
                    BookShelfView(
                        title: "Popular",
                        books: model.popularBooks,
                        savedBookIds: model.savedBookIds,
                        onToggleSaved: toggleSaved(_:),
                        onBookTapped: pushBook(_:)
                    )
                }

                // Journeys entry point (placeholder for P5.6)
                journeysBanner

                // Events entry point (placeholder for P5.7)
                eventsBanner

                // Browse by Category
                if !model.allCategories.isEmpty {
                    categoryBrowser
                }

                // Per-category shelves (first 4 categories)
                ForEach(model.booksByCategory.prefix(4), id: \.category) { group in
                    BookShelfView(
                        title: group.category,
                        books: group.books,
                        savedBookIds: model.savedBookIds,
                        onSeeAll: {
                            router.push(LibraryRoute.categoryDetail(category: group.category))
                        },
                        onToggleSaved: toggleSaved(_:),
                        onBookTapped: pushBook(_:)
                    )
                }
            }
            .padding(.bottom, .cfSpacing32)
        }
    }

    // MARK: - Journeys banner

    private var journeysBanner: some View {
        Button {
            onShowJourneys?()
        } label: {
            promoBanner(
                icon: "map.fill",
                iconColor: Color(hex: "#2D6A4F") ?? .green,
                title: "Reading Journeys",
                subtitle: "Curated paths through interconnected books",
                badge: "Coming Soon"
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .cfSpacing16)
        .accessibilityLabel("Reading Journeys — curated paths through interconnected books")
    }

    // MARK: - Events banner

    private var eventsBanner: some View {
        Button {
            onShowEvents?()
        } label: {
            promoBanner(
                icon: "star.fill",
                iconColor: Color(hex: "#C77DFF") ?? .purple,
                title: "Reading Events",
                subtitle: "Join community challenges and group reads",
                badge: "Coming Soon"
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .cfSpacing16)
        .accessibilityLabel("Reading Events — join community challenges and group reads")
    }

    private func promoBanner(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        badge: String?
    ) -> some View {
        HStack(spacing: .cfSpacing16) {
            ZStack {
                RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                HStack(spacing: .cfSpacing8) {
                    Text(title)
                        .font(.cfHeadline)
                        .foregroundStyle(Color.cfLabel)

                    if let badge {
                        Text(badge)
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfSecondaryLabel)
                            .padding(.horizontal, .cfSpacing8)
                            .padding(.vertical, .cfSpacing2)
                            .background(
                                Capsule().fill(Color.cfSecondaryFill)
                            )
                    }
                }

                Text(subtitle)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfTertiaryLabel)
        }
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16, style: .continuous))
    }

    // MARK: - Category browser

    private var categoryBrowser: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Browse by Category")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
                .padding(.horizontal, .cfSpacing16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: .cfSpacing8) {
                    ForEach(model.allCategories, id: \.self) { category in
                        categoryChip(category)
                    }
                }
                .padding(.horizontal, .cfSpacing16)
            }
        }
    }

    private func categoryChip(_ category: String) -> some View {
        Button {
            router.push(LibraryRoute.categoryDetail(category: category))
        } label: {
            Text(category)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfLabel)
                .padding(.horizontal, .cfSpacing16)
                .padding(.vertical, .cfSpacing8)
                .background(
                    RoundedRectangle(cornerRadius: .cfRadius20, style: .continuous)
                        .fill(Color.cfSecondaryBackground)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse \(category) books")
    }

    // MARK: - Category detail factory

    private func categoryDetailView(for category: String) -> some View {
        let booksInCategory: [BookCatalogItem]
        if category == "_new" {
            booksInCategory = model.newBooks
        } else {
            booksInCategory = model.books.filter { $0.categories.contains(category) }
        }
        let title = category == "_new" ? "New & Updated" : category
        return CategoryDetailView(
            category: title,
            books: booksInCategory,
            savedBookIds: model.savedBookIds,
            bookDetailRepository: bookDetailRepository,
            aiRepository: aiRepository,
            preferences: preferences,
            store: store,
            downloadManager: downloadManager,
            accountID: accountID,
            workPermit: workPermit,
            onToggleSaved: toggleSaved(_:),
            onOpenReader: onOpenReader,
            onShowPaywall: onShowPaywall
        )
    }

    // MARK: - Skeleton

    private var discoverSkeleton: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .cfSpacing32) {
                ForEach(0..<3, id: \.self) { _ in
                    BookShelfSkeleton()
                }
            }
            .padding(.top, .cfSpacing8)
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

    private func toggleSaved(_ bookId: String) {
        triggerHaptic()
        Task { await model.toggleSaved(bookId: bookId) }
    }

    private func pushBook(_ bookId: String) {
        router.push(LibraryRoute.bookDetail(bookId: bookId))
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Color hex helper (private to this file)

private extension Color {
    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Discover — loaded") {
    DiscoverView(
        repository: PreviewData.loadedRepo,
        bookDetailRepository: PreviewData.bookDetailInProgress,
        preferences: AppPreferences(keyPrefix: "preview.discover."),
        store: KeyValueStore(keyPrefix: "preview.discover."),
        userInterests: ["Productivity", "Psychology"]
    )
}

#Preview("Discover — no interests (popular fallback)") {
    DiscoverView(
        repository: PreviewData.loadedRepo,
        bookDetailRepository: PreviewData.bookDetailInProgress,
        preferences: AppPreferences(keyPrefix: "preview.discover."),
        store: KeyValueStore(keyPrefix: "preview.discover."),
        userInterests: []
    )
}

#Preview("Discover — skeleton", traits: .sizeThatFitsLayout) {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: .cfSpacing32) {
            ForEach(0..<3, id: \.self) { _ in
                BookShelfSkeleton()
            }
        }
        .padding(.vertical, .cfSpacing8)
    }
}

#Preview("Discover — error") {
    DiscoverView(
        repository: PreviewData.errorRepo,
        bookDetailRepository: PreviewData.bookDetailFreeLocked,
        preferences: AppPreferences(keyPrefix: "preview.discover."),
        store: KeyValueStore(keyPrefix: "preview.discover.")
    )
}

#Preview("Discover — dark mode") {
    DiscoverView(
        repository: PreviewData.loadedRepo,
        bookDetailRepository: PreviewData.bookDetailInProgress,
        preferences: AppPreferences(keyPrefix: "preview.discover."),
        store: KeyValueStore(keyPrefix: "preview.discover."),
        userInterests: ["Productivity"]
    )
    .preferredColorScheme(.dark)
}

#Preview("Discover — XXL text") {
    DiscoverView(
        repository: PreviewData.loadedRepo,
        bookDetailRepository: PreviewData.bookDetailInProgress,
        preferences: AppPreferences(keyPrefix: "preview.discover."),
        store: KeyValueStore(keyPrefix: "preview.discover."),
        userInterests: ["Productivity"]
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
