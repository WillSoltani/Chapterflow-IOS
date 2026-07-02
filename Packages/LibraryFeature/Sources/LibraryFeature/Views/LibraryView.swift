import SwiftUI
import Models
import DesignSystem
import CoreKit
#if canImport(UIKit)
import UIKit
#endif

/// The Library tab: a searchable, filterable catalog of all books.
///
/// Supports:
/// - Full-text search across title, author, and tags.
/// - Category chip filters.
/// - A "Saved" toggle to show only bookmarked books.
/// - Long-press / context-menu: save, start reading.
public struct LibraryView: View {

    @State private var model: LibraryModel
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
        _model = State(initialValue: LibraryModel(repository: repository))
        self.bookDetailRepository = bookDetailRepository
        self.onOpenReader = onOpenReader
        self.onShowPaywall = onShowPaywall
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationTitle("Library")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .searchable(text: $model.searchQuery, prompt: "Search books, authors, tags…")
                .toolbar { toolbarContent }
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
        case .loading where model.allBooks.isEmpty:
            BookListSkeleton()
                .padding(.top, .cfSpacing8)
        case .error(let msg):
            errorView(msg)
        default:
            catalogList
        }
    }

    private var catalogList: some View {
        List {
            // Category filter chips
            if !model.allCategories.isEmpty {
                Section {
                    categoryChips
                        .listRowInsets(EdgeInsets(top: .cfSpacing8, leading: .cfSpacing16,
                                                  bottom: .cfSpacing8, trailing: .cfSpacing16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

            }

            if model.filteredBooks.isEmpty {
                Section {
                    emptyFilterResult
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(model.filteredBooks) { book in
                        BookCardView(
                            book: book,
                            isSaved: model.savedBookIds.contains(book.bookId),
                            onSave: {
                                triggerHaptic()
                                Task { await model.toggleSaved(bookId: book.bookId) }
                            },
                            onTap: {
                                router.push(LibraryRoute.bookDetail(bookId: book.bookId))
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: .cfSpacing16,
                                                  bottom: 0, trailing: .cfSpacing16))
                        .listRowBackground(Color.cfBackground)
                        .contextMenu { bookContextMenu(for: book) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: model.filteredBooks.map(\.bookId))
    }

    // MARK: - Category chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .cfSpacing8) {
                // "All" chip
                categoryChip(nil)
                // Saved chip
                savedChip
                ForEach(model.allCategories, id: \.self) { cat in
                    categoryChip(cat)
                }
            }
        }
    }

    private func categoryChip(_ category: String?) -> some View {
        let isSelected = model.selectedCategory == category && !model.showSavedOnly
        let label = category ?? "All"
        return Button {
            model.showSavedOnly = false
            model.selectedCategory = isSelected ? nil : category
        } label: {
            Text(label)
                .font(.cfCaption)
                .padding(.horizontal, .cfSpacing12)
                .padding(.vertical, .cfSpacing8)
                .background(
                    Capsule().fill(isSelected ? Color.cfAccent : Color.cfSecondaryBackground)
                )
                .foregroundStyle(isSelected ? Color.white : Color.cfLabel)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var savedChip: some View {
        Button {
            model.selectedCategory = nil
            model.showSavedOnly.toggle()
        } label: {
            Label("Saved", systemImage: model.showSavedOnly ? "bookmark.fill" : "bookmark")
                .font(.cfCaption)
                .padding(.horizontal, .cfSpacing12)
                .padding(.vertical, .cfSpacing8)
                .background(
                    Capsule()
                        .fill(model.showSavedOnly ? Color.cfAccent : Color.cfSecondaryBackground)
                )
                .foregroundStyle(model.showSavedOnly ? Color.white : Color.cfLabel)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.showSavedOnly ? .isSelected : [])
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if model.loadState == .loading {
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityLabel("Loading")
            }
        }
    }

    // MARK: - Empty filter result

    private var emptyFilterResult: some View {
        ContentUnavailableView.search(text: model.searchQuery.isEmpty
            ? (model.showSavedOnly ? "saved books" : model.selectedCategory ?? "books")
            : model.searchQuery)
        .frame(maxWidth: .infinity)
        .padding(.top, .cfSpacing40)
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

    // MARK: - Context menu

    @ViewBuilder
    private func bookContextMenu(for book: BookCatalogItem) -> some View {
        let isSaved = model.savedBookIds.contains(book.bookId)

        Button {
            triggerHaptic()
            Task { await model.toggleSaved(bookId: book.bookId) }
        } label: {
            Label(isSaved ? "Remove from Saved" : "Save",
                  systemImage: isSaved ? "bookmark.slash" : "bookmark")
        }

        Button {
            router.push(LibraryRoute.bookDetail(bookId: book.bookId))
        } label: {
            Label("Start Reading", systemImage: "book")
        }

        Button {
            #if canImport(UIKit)
            let text = "\(book.title) by \(book.author)"
            let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(av, animated: true)
            }
            #endif
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: - Haptics

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Library — loaded") {
    LibraryView(repository: PreviewData.loadedRepo, bookDetailRepository: PreviewData.bookDetailInProgress)
}

#Preview("Library — empty catalog") {
    LibraryView(repository: PreviewData.emptyRepo, bookDetailRepository: PreviewData.bookDetailFreeLocked)
}

#Preview("Library — error") {
    LibraryView(repository: PreviewData.errorRepo, bookDetailRepository: PreviewData.bookDetailFreeLocked)
}

#Preview("Library — dark mode") {
    LibraryView(repository: PreviewData.loadedRepo, bookDetailRepository: PreviewData.bookDetailInProgress)
        .preferredColorScheme(.dark)
}

#Preview("Library — XXL text") {
    LibraryView(repository: PreviewData.loadedRepo, bookDetailRepository: PreviewData.bookDetailInProgress)
        .dynamicTypeSize(.accessibility3)
}
#endif
