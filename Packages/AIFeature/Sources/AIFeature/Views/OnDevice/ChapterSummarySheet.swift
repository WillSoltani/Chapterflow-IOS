import SwiftUI
import DesignSystem

// MARK: - Model

/// View model for the chapter summary sheet.
///
/// Holds the generation phase and the produced summary text.
/// Availability and feature-flag checks are performed before this model
/// is created — callers must gate the entry point behind
/// ``makeOnDeviceAIService(flag:)``'s availability.
@Observable
@MainActor
public final class ChapterSummaryModel {

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case generating
        case done(String)
        case failed(String)
    }

    // MARK: - State

    public private(set) var phase: Phase = .idle

    // MARK: - Config

    private let chapterTitle: String
    private let chapterText: String
    private let service: any OnDeviceAIProviding

    // MARK: - Init

    public init(
        chapterTitle: String,
        chapterText: String,
        service: any OnDeviceAIProviding
    ) {
        self.chapterTitle = chapterTitle
        self.chapterText = chapterText
        self.service = service
    }

    // MARK: - Actions

    public func generate() async {
        guard phase == .idle else { return }
        phase = .generating
        do {
            let summary = try await service.summarizeChapter(
                title: chapterTitle,
                text: chapterText
            )
            phase = .done(summary)
        } catch let aiError as OnDeviceAIError {
            switch aiError {
            case .unavailable:
                phase = .failed("On-device AI is not available on this device.")
            case .noContext:
                phase = .failed("No chapter text available to summarize.")
            case .emptyResponse:
                phase = .failed("The model returned an empty summary. Try again.")
            case .generationFailed(let msg):
                phase = .failed(msg)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func retry() {
        phase = .idle
    }
}

// MARK: - View

/// A sheet that shows an on-device generated summary of the current chapter.
///
/// Present this from the reader toolbar. The summary is generated lazily
/// on `.task` so it starts as soon as the sheet appears.
/// Entry points must be gated behind `OnDeviceAIAvailability.isAvailable`
/// and the feature flag — this view never checks those itself.
public struct ChapterSummarySheet: View {

    @State private var model: ChapterSummaryModel
    @Environment(\.dismiss) private var dismiss

    public init(model: ChapterSummaryModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Chapter Summary")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                .background(Color.cfGroupedBackground)
        }
        .task { await model.generate() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .generating:
            generatingView
        case .done(let summary):
            summaryScrollView(summary)
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var generatingView: some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.cfAccent)
            Text("Summarising…")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Generating chapter summary")
    }

    private func summaryScrollView(_ summary: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .cfSpacing24) {
                Text(summary)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                OnDevicePrivacyNote()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.cfSpacing24)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: .cfSpacing16) {
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
        }
        .padding(.cfSpacing24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Summary — generating (light)") {
    ChapterSummarySheet(
        model: ChapterSummaryModel(
            chapterTitle: "The Surprising Power of Atomic Habits",
            chapterText: "Sample chapter text…",
            service: FakeOnDeviceAIService(availability: .available, delay: 60)
        )
    )
}

#Preview("Summary — done (dark)") {
    ChapterSummarySheet(
        model: {
            let m = ChapterSummaryModel(
                chapterTitle: "The Surprising Power of Atomic Habits",
                chapterText: "Sample chapter text…",
                service: FakeOnDeviceAIService(availability: .available, delay: 0)
            )
            return m
        }()
    )
    .preferredColorScheme(.dark)
}

#Preview("Summary — done (XXL text)") {
    ChapterSummarySheet(
        model: ChapterSummaryModel(
            chapterTitle: "The Surprising Power of Atomic Habits",
            chapterText: "Sample chapter text…",
            service: FakeOnDeviceAIService(availability: .available, delay: 0)
        )
    )
    .dynamicTypeSize(.accessibility3)
}

#Preview("Summary — unavailable") {
    ChapterSummarySheet(
        model: ChapterSummaryModel(
            chapterTitle: "The Surprising Power of Atomic Habits",
            chapterText: "Sample chapter text…",
            service: FakeOnDeviceAIService(availability: .unavailableDeviceNotEligible)
        )
    )
}
#endif
