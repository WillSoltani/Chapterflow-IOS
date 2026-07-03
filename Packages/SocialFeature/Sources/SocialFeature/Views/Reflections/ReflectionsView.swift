import SwiftUI
import DesignSystem

/// The full reflections screen for a single chapter.
///
/// Shows a compose area at the top (so writing is the natural first action),
/// followed by the history of past reflections with AI feedback.
/// Calm, encouraging — no grading, no scores.
public struct ReflectionsView: View {

    @State private var model: ReflectionsModel
    @FocusState private var composeFocused: Bool

    public init(repository: any SocialRepository, bookId: String, chapterN: Int) {
        _model = State(initialValue: ReflectionsModel(
            repository: repository,
            bookId: bookId,
            chapterN: chapterN
        ))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .cfSpacing24) {
                    introHeader
                    composeCard
                    historySection
                }
                .padding(.horizontal, .cfSpacing16)
                .padding(.vertical, .cfSpacing20)
            }
            .background(Color.cfGroupedBackground.ignoresSafeArea())
            .navigationTitle("Reflect")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .refreshable { await model.load() }
        }
        .task { await model.load() }
    }

    // MARK: - Intro

    private var introHeader: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text("What stayed with you?")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
            Text("Write what resonated — no right answers, just your honest reaction. AI can offer a perspective when you're ready.")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Compose card

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            TextEditor(text: $model.draftText)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .focused($composeFocused)
                .accessibilityLabel("Write your reflection here")
                .overlay(alignment: .topLeading) {
                    if model.draftText.isEmpty {
                        Text("Jot down your thoughts…")
                            .font(.cfBody)
                            .foregroundStyle(Color.cfTertiaryLabel)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }

            if let error = model.submitError {
                Text(error)
                    .font(.cfCaption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                submitButton
            }
        }
        .padding(.cfSpacing16)
        .background(Color.cfBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    private var submitButton: some View {
        Button {
            composeFocused = false
            Task { await model.submitReflection() }
        } label: {
            Group {
                if model.isSubmitting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                } else {
                    Label("Save reflection", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.cfSubheadline)
            .foregroundStyle(model.canSubmit ? Color.cfAccent : Color.cfTertiaryLabel)
        }
        .buttonStyle(.plain)
        .disabled(!model.canSubmit)
        .accessibilityLabel("Save reflection")
        .accessibilityHint("Saves your reflection and attempts to sync it")
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        switch model.loadPhase {
        case .idle where model.items.isEmpty,
             .loading where model.items.isEmpty:
            historyPlaceholder
        case .error(let message) where model.items.isEmpty:
            errorView(message)
        default:
            historyList
        }
    }

    private var historyPlaceholder: some View {
        VStack(spacing: .cfSpacing12) {
            ProgressView()
            Text("Loading reflections…")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.cfSpacing32)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: .cfIconLarge))
                .foregroundStyle(Color.cfTertiaryLabel)
            Text("Couldn't load reflections")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            Text(message)
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.cfSpacing32)
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            if !model.items.isEmpty {
                Text("Your reflections")
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
            }

            if let error = model.feedbackError {
                feedbackErrorBanner(error)
            }

            ForEach(model.items) { item in
                ReflectionRowView(
                    item: item,
                    isFetchingFeedback: model.fetchingFeedbackForIds.contains(item.id),
                    onRequestFeedback: {
                        Task { await model.requestFeedback(for: item) }
                    }
                )
            }

            if model.items.isEmpty {
                emptyHistory
            }
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "text.bubble")
                .font(.system(size: .cfIconLarge))
                .foregroundStyle(Color.cfTertiaryLabel)
            Text("No reflections yet")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            Text("Write your first reflection above — it stays private and helps cement what you've learned.")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.cfSpacing32)
    }

    private func feedbackErrorBanner(_ message: String) -> some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.cfCaption)
        }
        .foregroundStyle(.red)
        .padding(.cfSpacing12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: .cfRadius8))
    }
}

// MARK: - ReflectionsModel convenience

private extension ReflectionsModel {
    var canSubmit: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Loaded – light") {
    let repo = FakeSocialRepository.reflectionsPreview
    ReflectionsView(repository: repo, bookId: "atomic-habits", chapterN: 3)
}

#Preview("Loaded – dark") {
    let repo = FakeSocialRepository.reflectionsPreview
    ReflectionsView(repository: repo, bookId: "atomic-habits", chapterN: 3)
        .preferredColorScheme(.dark)
}

#Preview("Empty state") {
    let repo = FakeSocialRepository()
    ReflectionsView(repository: repo, bookId: "atomic-habits", chapterN: 1)
}

#Preview("XXL Dynamic Type") {
    let repo = FakeSocialRepository.reflectionsPreview
    ReflectionsView(repository: repo, bookId: "atomic-habits", chapterN: 3)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Offline / error") {
    let repo = FakeSocialRepository(error: .offline)
    ReflectionsView(repository: repo, bookId: "atomic-habits", chapterN: 1)
}
#endif
