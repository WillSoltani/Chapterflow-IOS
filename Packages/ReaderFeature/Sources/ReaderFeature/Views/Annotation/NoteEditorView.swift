import SwiftUI
import DesignSystem

/// A modal sheet for composing and saving an annotation note.
///
/// Presented by `ReaderControlSurface` when `AnnotationModel.isShowingNoteEditor` is `true`.
struct NoteEditorView: View {
    @Bindable var model: AnnotationModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: .cfSpacing16) {
                TextEditor(text: $text)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                    .focused($focused)
                    .padding(.cfSpacing4)
                    .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius8))
                    .frame(minHeight: 140)

                Spacer()
            }
            .padding(.cfSpacing20)
            .navigationTitle("Add Note")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.isShowingNoteEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveNote(content: text)
                        model.isShowingNoteEditor = false
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { focused = true }
    }
}

#if DEBUG
#Preview("NoteEditorView") {
    NoteEditorView(model: AnnotationModel(
        bookId: "book-1",
        chapterId: "ch-1",
        variantKey: "medium",
        toneKey: "gentle",
        repository: FakeAnnotationRepository()
    ))
}
#endif
