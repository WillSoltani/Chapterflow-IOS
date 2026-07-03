import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - NotebookHubView

/// The Notebook + Saved hub.
///
/// Tab picker selects between the searchable/filterable Notebook list and the Saved shelf.
/// Tapping a notebook entry opens a detail sheet; tapping a saved book calls `onBookTap`.
public struct NotebookHubView: View {

    private let notebookModel: NotebookModel
    private let savedModel: SavedBooksModel
    private let onNavigateToChapter: ((bookId: String, chapterNumber: Int)) -> Void
    private let onBookTap: (String) -> Void

    @State private var selectedTab: HubTab = .notebook
    @State private var selectedEntry: NotebookEntry?
    @State private var showSearch = false

    public init(
        notebookModel: NotebookModel,
        savedModel: SavedBooksModel,
        onNavigateToChapter: @escaping ((bookId: String, chapterNumber: Int)) -> Void,
        onBookTap: @escaping (String) -> Void
    ) {
        self.notebookModel = notebookModel
        self.savedModel = savedModel
        self.onNavigateToChapter = onNavigateToChapter
        self.onBookTap = onBookTap
    }

    enum HubTab: String, CaseIterable {
        case notebook = "Notebook"
        case saved = "Saved"
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { notebookModel.searchText },
            set: { notebookModel.searchText = $0 }
        )
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker

                if selectedTab == .notebook {
                    notebookContent
                } else {
                    SavedShelfView(model: savedModel, onBookTap: onBookTap)
                }
            }
            .background(Color.cfGroupedBackground.ignoresSafeArea())
            .navigationTitle("My Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            #if os(iOS)
            .searchable(
                text: searchTextBinding,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search notes, highlights, tags…"
            )
            #else
            .searchable(text: searchTextBinding, prompt: "Search notes, highlights, tags…")
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if selectedTab == .notebook && notebookModel.hasActiveFilters {
                        Button("Clear") { notebookModel.clearFilters() }
                            .foregroundStyle(Color.cfAccent)
                    }
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            NotebookEntryDetailSheet(
                entry: entry,
                onSave: { content, tags in
                    Task { await notebookModel.saveEdit(
                        entryId: entry.entryId, content: content, tags: tags
                    ) }
                },
                onDelete: {
                    Task { await notebookModel.deleteEntry(entryId: entry.entryId) }
                },
                onNavigateToChapter: onNavigateToChapter
            )
        }
        .task { notebookModel.load() }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("Section", selection: $selectedTab) {
            ForEach(HubTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing12)
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Notebook content

    private var notebookContent: some View {
        Group {
            switch notebookModel.loadState {
            case .loading:
                notebookSkeleton
            case .loaded:
                if notebookModel.allEntries.isEmpty {
                    notebookEmptyState
                } else {
                    notebookList
                }
            case .error(let error):
                notebookError(error)
            }
        }
    }

    // MARK: - Notebook list

    private var notebookList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Type filter pills
                typeFilterRow

                // Tag filter chips (only when tags exist)
                if !notebookModel.availableTags.isEmpty {
                    tagFilterRow
                        .padding(.bottom, .cfSpacing8)
                }

                // Result count when filtered
                if notebookModel.hasActiveFilters {
                    HStack {
                        Text("\(notebookModel.filteredEntries.count) result\(notebookModel.filteredEntries.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Color.cfSecondaryLabel)
                        Spacer()
                    }
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.bottom, .cfSpacing8)
                }

                if notebookModel.filteredEntries.isEmpty {
                    noResultsView
                } else {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(notebookModel.filteredEntries) { entry in
                            NotebookEntryRowView(entry: entry)
                                .padding(.horizontal, .cfSpacing16)
                                .padding(.vertical, .cfSpacing4)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedEntry = entry }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await notebookModel.deleteEntry(entryId: entry.entryId) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                    .background(Color.cfBackground)
                    .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
                    .padding(.horizontal, .cfSpacing16)
                }
            }
            .padding(.bottom, .cfSpacing40)
        }
        .refreshable { await notebookModel.refresh() }
    }

    // MARK: - Type filter row

    private var typeFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .cfSpacing8) {
                TypeFilterChip(
                    label: "All",
                    systemImage: "square.grid.2x2",
                    isSelected: notebookModel.selectedTypeFilter == nil
                ) {
                    notebookModel.selectedTypeFilter = nil
                }
                ForEach(NotebookEntryType.allCases, id: \.rawValue) { type in
                    TypeFilterChip(
                        label: type.displayName,
                        systemImage: type.systemImage,
                        isSelected: notebookModel.selectedTypeFilter == type
                    ) {
                        notebookModel.selectedTypeFilter = (notebookModel.selectedTypeFilter == type)
                            ? nil : type
                    }
                }
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing8)
        }
    }

    // MARK: - Tag filter row

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .cfSpacing8) {
                ForEach(notebookModel.availableTags, id: \.self) { tag in
                    TagChip(
                        tag: tag,
                        isSelected: notebookModel.selectedTags.contains(tag)
                    )
                    .onTapGesture { notebookModel.toggleTag(tag) }
                }
            }
            .padding(.horizontal, .cfSpacing16)
        }
    }

    // MARK: - Empty / no-results states

    private var notebookEmptyState: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(Color.cfTertiaryLabel)
            Text("No Notes Yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.cfLabel)
            Text("Highlights, notes, and bookmarks you make while reading will appear here.")
                .font(.callout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .cfSpacing32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.cfSpacing48)
    }

    private var noResultsView: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Color.cfTertiaryLabel)
            Text("No Results")
                .font(.headline)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.cfSpacing48)
    }

    private var notebookSkeleton: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    NotebookRowSkeleton()
                    Divider().padding(.leading, 56)
                }
            }
            .background(Color.cfBackground)
            .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
            .padding(.cfSpacing16)
        }
    }

    private func notebookError(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.cfSecondaryLabel)
            Text("Couldn't Load Notebook")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .cfSpacing24)
            Button("Retry") { Task { await notebookModel.refresh() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.cfAccent)
        }
        .padding(.cfSpacing32)
    }
}

// MARK: - TypeFilterChip

private struct TypeFilterChip: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.cfBackground : Color.cfLabel)
                .padding(.horizontal, .cfSpacing12)
                .padding(.vertical, .cfSpacing8)
                .background(
                    isSelected ? Color.cfAccent : Color.cfSecondaryBackground,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Row skeleton

private struct NotebookRowSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            RoundedRectangle(cornerRadius: .cfRadius4)
                .fill(Color.cfSecondaryBackground)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                RoundedRectangle(cornerRadius: .cfRadius4)
                    .fill(Color.cfSecondaryBackground)
                    .frame(height: 14)
                    .frame(maxWidth: 200)
                RoundedRectangle(cornerRadius: .cfRadius4)
                    .fill(Color.cfSecondaryBackground)
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: .cfRadius4)
                    .fill(Color.cfSecondaryBackground)
                    .frame(height: 12)
                    .frame(maxWidth: 160)
            }
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing12)
        .redacted(reason: .placeholder)
    }
}

// MARK: - Previews

#Preview("Notebook Hub — Light") {
    NotebookHubView(
        notebookModel: .preview,
        savedModel: .preview,
        onNavigateToChapter: { _ in },
        onBookTap: { _ in }
    )
}

#Preview("Notebook Hub — Dark") {
    NotebookHubView(
        notebookModel: .preview,
        savedModel: .preview,
        onNavigateToChapter: { _ in },
        onBookTap: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Notebook Hub — XXL Text") {
    NotebookHubView(
        notebookModel: .preview,
        savedModel: .preview,
        onNavigateToChapter: { _ in },
        onBookTap: { _ in }
    )
    .dynamicTypeSize(.accessibility3)
}
