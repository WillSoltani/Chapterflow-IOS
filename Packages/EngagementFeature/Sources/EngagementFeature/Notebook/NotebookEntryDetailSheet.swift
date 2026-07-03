import SwiftUI
import DesignSystem
import Models

// MARK: - NotebookEntryDetailSheet

/// Full-screen sheet for viewing, editing, and deleting a notebook entry.
///
/// Editable fields: `content` (text body) and `tags` (comma-separated chip input).
/// Non-editable: `quote`, book/chapter context, type.
struct NotebookEntryDetailSheet: View {

    let entry: NotebookEntry
    let onSave: (String, [String]) -> Void
    let onDelete: () -> Void
    let onNavigateToChapter: ((bookId: String, chapterNumber: Int)) -> Void

    @State private var editContent: String
    @State private var tagInput: String
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(
        entry: NotebookEntry,
        onSave: @escaping (String, [String]) -> Void,
        onDelete: @escaping () -> Void,
        onNavigateToChapter: @escaping ((bookId: String, chapterNumber: Int)) -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onDelete = onDelete
        self.onNavigateToChapter = onNavigateToChapter
        _editContent = State(initialValue: entry.content ?? "")
        _tagInput = State(initialValue: entry.effectiveTags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing20) {
                    // Context header
                    contextSection

                    // Quote (read-only)
                    if let quote = entry.quote, !quote.isEmpty {
                        quoteSection(quote)
                    }

                    // Content
                    contentSection

                    // Tags
                    tagsSection

                    // Navigate to chapter button
                    if let chapterNum = entry.chapterNumber {
                        navigateButton(chapterNum: chapterNum)
                    }

                    Spacer(minLength: .cfSpacing40)
                }
                .padding(.cfSpacing16)
            }
            .background(Color.cfGroupedBackground.ignoresSafeArea())
            .navigationTitle(entry.type.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(isEditing ? "Stop Editing" : "Edit") {
                            if isEditing { saveChanges() }
                            isEditing.toggle()
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveChanges() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .confirmationDialog(
                "Delete Entry",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This entry will be removed from your notebook.")
            }
        }
    }

    // MARK: - Sub-views

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: entry.type.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(Color.cfAccent)
                Text(entry.type.displayName)
                    .font(.subheadline)
                    .foregroundStyle(Color.cfAccent)
            }
            if let bookTitle = entry.bookTitle {
                Text(bookTitle)
                    .font(.headline)
                    .foregroundStyle(Color.cfLabel)
            }
            if let chapterTitle = entry.chapterTitle,
               let chapterNum = entry.chapterNumber {
                Text("Chapter \(chapterNum): \(chapterTitle)")
                    .font(.subheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
            } else if let chapterNum = entry.chapterNumber {
                Text("Chapter \(chapterNum)")
                    .font(.subheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
    }

    private func quoteSection(_ quote: String) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Label("Excerpt", systemImage: "text.quote")
                .font(.caption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(quote)
                .font(.body)
                .italic()
                .foregroundStyle(Color.cfSecondaryLabel)
                .padding(.cfSpacing12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius8))
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Label("Note", systemImage: "pencil")
                .font(.caption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .textCase(.uppercase)
                .tracking(0.6)

            if isEditing {
                TextEditor(text: $editContent)
                    .font(.body)
                    .foregroundStyle(Color.cfLabel)
                    .frame(minHeight: 120)
                    .padding(.cfSpacing8)
                    .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius8))
                    .overlay(
                        RoundedRectangle(cornerRadius: .cfRadius8)
                            .stroke(Color.cfAccent, lineWidth: 1)
                    )
            } else {
                Text(editContent.isEmpty ? "No content" : editContent)
                    .font(.body)
                    .foregroundStyle(editContent.isEmpty ? Color.cfTertiaryLabel : Color.cfLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.cfSpacing12)
                    .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius8))
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Label("Tags", systemImage: "tag")
                .font(.caption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .textCase(.uppercase)
                .tracking(0.6)

            if isEditing {
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    TextField("Add tags, separated by commas", text: $tagInput)
                        .font(.body)
                        .padding(.cfSpacing12)
                        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius8))
                        .overlay(
                            RoundedRectangle(cornerRadius: .cfRadius8)
                                .stroke(Color.cfAccent, lineWidth: 1)
                        )
                    Text("Separate tags with commas")
                        .font(.caption)
                        .foregroundStyle(Color.cfTertiaryLabel)
                }
            } else {
                let tags = parsedTags(from: tagInput)
                if tags.isEmpty {
                    Text("No tags")
                        .font(.body)
                        .foregroundStyle(Color.cfTertiaryLabel)
                } else {
                    FlowLayout(spacing: .cfSpacing8) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag, isSelected: false)
                        }
                    }
                }
            }
        }
    }

    private func navigateButton(chapterNum: Int) -> some View {
        Button {
            guard !entry.bookId.isEmpty else { return }
            onNavigateToChapter((bookId: entry.bookId, chapterNumber: chapterNum))
            dismiss()
        } label: {
            Label("Open Source Chapter", systemImage: "arrow.right.circle")
                .font(.callout)
                .foregroundStyle(Color.cfAccent)
                .frame(maxWidth: .infinity)
                .padding(.cfSpacing12)
                .background(Color.cfAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .accessibilityHint("Opens the chapter where this entry was made")
    }

    // MARK: - Helpers

    private func saveChanges() {
        let tags = parsedTags(from: tagInput)
        onSave(editContent, tags)
        isEditing = false
    }

    private func parsedTags(from input: String) -> [String] {
        input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - FlowLayout

/// A simple wrapping HStack for tag chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width + (rowWidth > 0 ? spacing : 0) > maxWidth {
                width = max(width, rowWidth)
                height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
                rowHeight = max(rowHeight, size.height)
            }
        }
        return CGSize(width: max(width, rowWidth), height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview("Detail Sheet — Note") {
    NotebookEntryDetailSheet(
        entry: NotebookEntry.previewEntries[0],
        onSave: { _, _ in },
        onDelete: {},
        onNavigateToChapter: { _ in }
    )
}

#Preview("Detail Sheet — Highlight") {
    NotebookEntryDetailSheet(
        entry: NotebookEntry.previewEntries[2],
        onSave: { _, _ in },
        onDelete: {},
        onNavigateToChapter: { _ in }
    )
    .preferredColorScheme(.dark)
}
