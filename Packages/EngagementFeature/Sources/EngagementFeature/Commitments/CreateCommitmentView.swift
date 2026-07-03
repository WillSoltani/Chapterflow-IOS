import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - CreateCommitmentView

/// Modal sheet for composing a new if-then implementation commitment.
///
/// The user picks 3- or 7-day follow-up, writes the "if" trigger and "then" action,
/// and confirms. On success the sheet dismisses and the parent list refreshes.
public struct CreateCommitmentView: View {

    private let model: CommitmentsModel
    private let context: CommitmentsView.CreateContext?

    @Environment(\.dismiss) private var dismiss

    @State private var ifText: String = ""
    @State private var thenText: String = ""
    @State private var followUpDays: Int = 7
    @State private var bookId: String = ""
    @State private var chapterId: String = ""
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false

    private var canSave: Bool {
        !ifText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !thenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!bookId.isEmpty || context != nil)
    }

    public init(model: CommitmentsModel, context: CommitmentsView.CreateContext? = nil) {
        self.model = model
        self.context = context
        if let context {
            self._bookId = State(initialValue: context.bookId)
            self._chapterId = State(initialValue: context.chapterId)
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    headerCard
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init())

                Section("If this happens…") {
                    TextField("e.g. I sit down to plan my week", text: $ifText, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(.cfBody)
                        .accessibilityLabel("Trigger situation — if this happens")
                }

                Section("Then I will…") {
                    TextField("e.g. identify the one most important task first", text: $thenText, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(.cfBody)
                        .accessibilityLabel("Intended action — then I will")
                }

                if context == nil {
                    Section("Book context") {
                        TextField("Book ID", text: $bookId)
                            .font(.cfBody)
                            .accessibilityLabel("Book ID")
                        TextField("Chapter ID", text: $chapterId)
                            .font(.cfBody)
                            .accessibilityLabel("Chapter ID")
                    }
                }

                Section("Follow-up reminder") {
                    Picker("Check in after", selection: $followUpDays) {
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Follow-up reminder interval")

                    followUpDatePreview
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.cfFootnote)
                            .foregroundStyle(Color.red)
                    }
                }
            }
            .navigationTitle("New commitment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel creating commitment")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                            .accessibilityLabel("Save commitment")
                    }
                }
            }
        }
    }

    // MARK: - Sub-views

    private var headerCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                HStack(spacing: .cfSpacing12) {
                    Image(systemName: "bolt.fill")
                        .font(.title2)
                        .foregroundStyle(Color.cfAccent)
                        .accessibilityHidden(true)
                    Text("Implementation intention")
                        .font(.cfHeadline)
                        .foregroundStyle(Color.cfLabel)
                }
                Text("Research shows specifying *when*, *where*, and *how* you'll act doubles follow-through.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            .padding(.cfSpacing4)
        }
        .padding(.cfSpacing16)
    }

    private var followUpDatePreview: some View {
        let followUp = Calendar.current.date(byAdding: .day, value: followUpDays, to: Date()) ?? Date()
        let formatted = followUp.formatted(date: .long, time: .omitted)
        return HStack {
            Image(systemName: "bell")
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)
            Text("Reminder on \(formatted)")
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        errorMessage = nil
        let bid = context?.bookId ?? bookId
        let cid = context?.chapterId ?? chapterId
        let trimmedIf = ifText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedThen = thenText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await model.createCommitment(
                bookId: bid,
                chapterId: cid,
                ifStatement: trimmedIf,
                thenStatement: trimmedThen,
                followUpDays: followUpDays
            )
            dismiss()
        } catch {
            isSaving = false
            errorMessage = "Failed to save commitment. Please try again."
        }
    }
}

// MARK: - Previews

#Preview("Create sheet — light") {
    CreateCommitmentView(
        model: CommitmentsModel.preview,
        context: CommitmentsView.CreateContext(bookId: "atomic-habits", chapterId: "ch-4")
    )
}

#Preview("Create sheet — dark") {
    CreateCommitmentView(
        model: CommitmentsModel.preview,
        context: CommitmentsView.CreateContext(bookId: "atomic-habits", chapterId: "ch-4")
    )
    .preferredColorScheme(.dark)
}

#Preview("Create sheet — XXL") {
    CreateCommitmentView(
        model: CommitmentsModel.preview,
        context: CommitmentsView.CreateContext(bookId: "atomic-habits", chapterId: "ch-4")
    )
    .dynamicTypeSize(.accessibility2)
}
