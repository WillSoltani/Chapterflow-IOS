import SwiftUI
import DesignSystem
import Persistence

/// A chat-style sheet for asking questions about a specific book.
///
/// Present this sheet from ``BookDetailView`` or the reader screen.
/// Pass `onJumpToChapter` to enable tappable citation chips that navigate
/// to the cited chapter; pass `selectionContext` when the user has a
/// passage highlighted so the answer is grounded in that excerpt.
///
/// The conversation thread lives in `model` for the duration of the session.
/// To preserve the thread across dismissals, keep the `model` instance alive
/// in the presenting view's state.
public struct AskTheBookSheet: View {

    @State private var model: AskTheBookModel

    public init(model: AskTheBookModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                scrollArea
                inputArea
            }
            .navigationTitle("Ask the Book")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .background(Color.cfGroupedBackground)
        }
    }

    // MARK: - Scroll area

    private var scrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: .cfSpacing16) {
                    quotaHeader
                        .padding(.top, .cfSpacing16)

                    if let context = model.selectionContext {
                        selectionContextBanner(context)
                    }

                    ForEach(model.messages) { message in
                        AskMessageView(message: message) { chapterNumber in
                            model.jumpToChapter(chapterNumber)
                        }
                        .id(message.id)
                    }

                    phaseView
                        .id("phaseAnchor")

                    // Spacer so messages aren't hidden behind the input bar.
                    Color.clear.frame(height: 80)
                }
            }
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("phaseAnchor", anchor: .bottom)
                }
            }
            .onChange(of: model.phase) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("phaseAnchor", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Phase overlays

    @ViewBuilder
    private var phaseView: some View {
        switch model.phase {
        case .idle:
            if model.messages.isEmpty {
                emptyPromptView
            }
        case .asking:
            askingIndicator
        case .rateLimited(let resetsAt):
            rateLimitedView(resetsAt: resetsAt)
        case .error(let message):
            errorView(message: message)
        case .offline:
            offlineView
        }
    }

    // MARK: - Empty state prompt

    private var emptyPromptView: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.cfAccent)

            VStack(spacing: .cfSpacing4) {
                Text("Ask anything about this book")
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                Text("Get answers grounded in the book's content,\nwith citations to the source chapters.")
                    .font(.cfCallout)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
            }

            if model.isOnDeviceWired {
                OnDevicePrivacyNote()
            }
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Loading indicator

    private var askingIndicator: some View {
        HStack(spacing: .cfSpacing12) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.cfAccent)
            Text("Thinking…")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .padding(.horizontal, .cfSpacing24)
        .padding(.vertical, .cfSpacing12)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, .cfSpacing16)
        .accessibilityLabel("Looking up your answer")
    }

    // MARK: - Rate limit

    private func rateLimitedView(resetsAt: Date?) -> some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(Color.cfAccent)

            Text("You've reached today's questions")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)

            Group {
                if let reset = resetsAt {
                    Text("Resets \(reset, style: .relative) from now")
                } else {
                    Text("Questions reset at midnight.")
                }
            }
            .font(.cfCallout)
            .foregroundStyle(Color.cfSecondaryLabel)
            .multilineTextAlignment(.center)
        }
        .padding(.cfSpacing24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.yellow)

            Text(message)
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)

            Button("Try Again") { model.retry() }
                .buttonStyle(.borderedProminent)
                .tint(Color.cfAccent)
                .controlSize(.regular)
        }
        .padding(.cfSpacing24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Offline

    private var offlineView: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32))
                .foregroundStyle(Color.cfSecondaryLabel)

            Text("You're offline")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)

            Text("Asking the book requires a connection.\nCheck your network and try again.")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)

            Button("Retry") { model.retry() }
                .buttonStyle(.borderedProminent)
                .tint(Color.cfAccent)
                .controlSize(.regular)
        }
        .padding(.cfSpacing24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quota header

    @ViewBuilder
    private var quotaHeader: some View {
        if let remaining = model.remainingQuota {
            HStack {
                Spacer()
                Text(remaining == 1 ? "1 question remaining today" : "\(remaining) questions remaining today")
                    .font(.cfCaption)
                    .foregroundStyle(remaining <= 1 ? Color.orange : Color.cfSecondaryLabel)
                    .padding(.horizontal, .cfSpacing12)
                    .padding(.vertical, .cfSpacing4)
                    .background(
                        Capsule()
                            .fill(remaining <= 1 ? Color.orange.opacity(0.1) : Color.cfSecondaryFill)
                    )
                Spacer()
            }
            .padding(.horizontal, .cfSpacing16)
            .accessibilityLabel("\(remaining) AI questions remaining today")
        }
    }

    // MARK: - Selection context banner

    private func selectionContextBanner(_ context: String) -> some View {
        HStack(alignment: .top, spacing: .cfSpacing8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.cfAccent)

            Text(context)
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.cfSpacing12)
        .background(
            RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous)
                .fill(Color.cfAccent.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous)
                        .strokeBorder(Color.cfAccent.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, .cfSpacing16)
        .accessibilityLabel("Context from your selection: \(context)")
    }

    // MARK: - Input area

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
            AskInputBar(
                text: $model.inputText,
                isSending: model.phase == .asking,
                canSend: model.canSend
            ) {
                Task { await model.sendQuestion() }
            }
        }
        .background(Color.cfGroupedBackground)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {}
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Ask — idle (light)") {
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(delay: 0)
    )
    return AskTheBookSheet(model: model)
}

#Preview("Ask — with context (dark)") {
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(delay: 0),
        selectionContext: "Habits are the compound interest of self-improvement. The same way that money multiplies through compound interest, the effects of your habits multiply as you repeat them."
    )
    return AskTheBookSheet(model: model)
        .preferredColorScheme(.dark)
}

#Preview("Ask — thread loaded") {
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(delay: 0)
    )
    // Seed the thread directly
    Task { @MainActor in
        model.inputText = "What is the core concept?"
        await model.sendQuestion()
    }
    return AskTheBookSheet(model: model)
}

#Preview("Ask — rate limited") {
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(error: FakeAIRepository.rateLimitedError, delay: 0)
    )
    Task { @MainActor in
        model.inputText = "Test"
        await model.sendQuestion()
    }
    return AskTheBookSheet(model: model)
}

#Preview("Ask — offline (no on-device)") {
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(error: FakeAIRepository.offlineError, delay: 0)
    )
    Task { @MainActor in
        model.inputText = "Test"
        await model.sendQuestion()
    }
    return AskTheBookSheet(model: model)
}

#Preview("Ask — offline answered on-device (light)") {
    let chapterText = """
    Habits are the compound interest of self-improvement. The effects of your habits multiply \
    as you repeat them. Small changes often appear to make no difference until you cross a \
    critical threshold. The most powerful outcomes of any compounding process are delayed.
    """
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(error: FakeAIRepository.offlineError, delay: 0),
        chapterText: chapterText,
        onDeviceService: FakeOnDeviceAIService(availability: .available, delay: 0)
    )
    Task { @MainActor in
        model.inputText = "What is the core concept?"
        await model.sendQuestion()
    }
    return AskTheBookSheet(model: model)
}

#Preview("Ask — offline answered on-device (dark)") {
    let chapterText = "Habits are the compound interest of self-improvement."
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(error: FakeAIRepository.offlineError, delay: 0),
        chapterText: chapterText,
        onDeviceService: FakeOnDeviceAIService(availability: .available, delay: 0)
    )
    Task { @MainActor in
        model.inputText = "What is the core concept?"
        await model.sendQuestion()
    }
    return AskTheBookSheet(model: model)
        .preferredColorScheme(.dark)
}

#Preview("Ask — on-device wired, idle with privacy note") {
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(delay: 0),
        chapterText: "Habits are the compound interest of self-improvement.",
        onDeviceService: FakeOnDeviceAIService(availability: .available)
    )
    return AskTheBookSheet(model: model)
}

#Preview("Ask — XXL text") {
    let model = AskTheBookModel(
        bookId: "b-atomic-habits",
        repository: FakeAIRepository(delay: 0)
    )
    return AskTheBookSheet(model: model)
        .dynamicTypeSize(.accessibility3)
}
#endif
