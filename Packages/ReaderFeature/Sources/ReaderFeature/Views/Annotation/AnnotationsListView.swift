import SwiftUI
import Persistence
import DesignSystem

/// A sheet listing all annotations for the chapter, grouped by type.
///
/// Tapping a highlight scrolls the reader to its anchored block via `onJumpToBlock`.
struct AnnotationsListView: View {
    @Bindable var model: AnnotationModel
    /// Called when the user taps an annotation that has a block anchor.
    let onJumpToBlock: (Int) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.annotations.isEmpty {
                    emptyState
                } else {
                    annotationList
                }
            }
            .navigationTitle("My Highlights")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.isShowingAnnotationsList = false
                    }
                }
            }
        }
    }

    // MARK: - Content

    private var annotationList: some View {
        List {
            let highlights = model.annotations.filter { $0.type == "highlight" }
            let notes = model.annotations.filter { $0.type == "note" }
            let bookmarks = model.annotations.filter { $0.type == "bookmark" }

            if !highlights.isEmpty {
                Section("Highlights") {
                    ForEach(highlights, id: \.annotationId) { ann in
                        HighlightRow(annotation: ann, onJump: {
                            if let blockIndex = anchorBlockIndex(for: ann) {
                                model.isShowingAnnotationsList = false
                                onJumpToBlock(blockIndex)
                            }
                        }, onDelete: {
                            model.deleteAnnotation(ann)
                        })
                    }
                }
            }

            if !notes.isEmpty {
                Section("Notes") {
                    ForEach(notes, id: \.annotationId) { ann in
                        NoteRow(annotation: ann, onJump: {
                            if let blockIndex = anchorBlockIndex(for: ann) {
                                model.isShowingAnnotationsList = false
                                onJumpToBlock(blockIndex)
                            }
                        }, onDelete: {
                            model.deleteAnnotation(ann)
                        })
                    }
                }
            }

            if !bookmarks.isEmpty {
                Section("Bookmark") {
                    ForEach(bookmarks, id: \.annotationId) { ann in
                        HStack {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.cfAccent)
                            Text("Chapter bookmarked")
                                .font(.cfBody)
                                .foregroundStyle(Color.cfLabel)
                            Spacer()
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                model.deleteAnnotation(ann)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
    }

    private var emptyState: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "highlighter")
                .font(.system(size: 44))
                .foregroundStyle(Color.cfTertiaryLabel)
            Text("No highlights yet")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
            Text("Long-press any paragraph to highlight it.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Private helpers

    private func anchorBlockIndex(for annotation: LocalAnnotation) -> Int? {
        annotation.anchorJSON.flatMap { AnnotationAnchor.from(json: $0) }?.blockIndex
    }
}

// MARK: - Row views

private struct HighlightRow: View {
    let annotation: LocalAnnotation
    let onJump: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onJump) {
            HStack(alignment: .top, spacing: .cfSpacing12) {
                RoundedRectangle(cornerRadius: .cfRadius4)
                    .fill(highlightColor)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(annotation.snippet ?? "")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(3)

                    if let anchorJSON = annotation.anchorJSON,
                       let anchor = AnnotationAnchor.from(json: anchorJSON) {
                        Text("\(anchor.variantKey.capitalized) · \(anchor.toneKey.capitalized)")
                            .font(.cfCaption2)
                            .foregroundStyle(Color.cfSecondaryLabel)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel("Highlight: \(annotation.snippet ?? "")")
    }

    private var highlightColor: Color {
        HighlightColor(rawValue: annotation.colorRaw ?? "yellow")?.solidColor ?? .yellow
    }
}

private struct NoteRow: View {
    let annotation: LocalAnnotation
    let onJump: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onJump) {
            VStack(alignment: .leading, spacing: .cfSpacing4) {
                if let snippet = annotation.snippet {
                    Text(snippet)
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .lineLimit(2)
                }
                Text(annotation.content ?? "")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                    .lineLimit(4)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel("Note: \(annotation.content ?? "")")
    }
}

#if DEBUG
#Preview("AnnotationsListView — empty") {
    AnnotationsListView(
        model: AnnotationModel(
            bookId: "b1",
            chapterId: "c1",
            variantKey: "medium",
            toneKey: "gentle",
            repository: FakeAnnotationRepository()
        ),
        onJumpToBlock: { _ in }
    )
}
#endif
