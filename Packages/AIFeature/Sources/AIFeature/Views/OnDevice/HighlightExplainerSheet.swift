import SwiftUI
import DesignSystem

// MARK: - Model

/// View model for the "Explain this highlight" sheet.
@Observable
@MainActor
public final class HighlightExplainerModel {

    public enum Phase: Equatable {
        case idle
        case generating
        case done(String)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    private let highlight: String
    private let chapterText: String
    private let service: any OnDeviceAIProviding

    public init(
        highlight: String,
        chapterText: String,
        service: any OnDeviceAIProviding
    ) {
        self.highlight = highlight
        self.chapterText = chapterText
        self.service = service
    }

    public func generate() async {
        guard phase == .idle else { return }
        phase = .generating
        do {
            let explanation = try await service.explainHighlight(highlight, chapterText: chapterText)
            phase = .done(explanation)
        } catch let aiError as OnDeviceAIError {
            switch aiError {
            case .unavailable:
                phase = .failed("On-device AI is not available on this device.")
            case .noContext:
                phase = .failed("No passage to explain.")
            case .emptyResponse:
                phase = .failed("The model returned an empty explanation. Try again.")
            case .generationFailed(let msg):
                phase = .failed(msg)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func retry() { phase = .idle }
}

// MARK: - View

/// A sheet that shows a plain-language explanation of a highlighted passage.
///
/// Present from the annotation popover when the user selects "Explain simply."
/// Entry points must be gated behind `OnDeviceAIAvailability.isAvailable`.
public struct HighlightExplainerSheet: View {

    @State private var model: HighlightExplainerModel
    @Environment(\.dismiss) private var dismiss

    public init(model: HighlightExplainerModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Explain Simply")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                .background(Color.cfGroupedBackground)
        }
        .task { await model.generate() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .generating:
            generatingView
        case .done(let explanation):
            explanationView(explanation)
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var generatingView: some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.cfAccent)
            Text("Explaining…")
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Generating explanation")
    }

    private func explanationView(_ explanation: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .cfSpacing24) {
                Text(explanation)
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
#Preview("Explainer — generating (light)") {
    HighlightExplainerSheet(
        model: HighlightExplainerModel(
            highlight: "Habits are the compound interest of self-improvement.",
            chapterText: "Sample chapter text about habit formation…",
            service: FakeOnDeviceAIService(availability: .available, delay: 60)
        )
    )
}

#Preview("Explainer — done (dark)") {
    HighlightExplainerSheet(
        model: HighlightExplainerModel(
            highlight: "Habits are the compound interest of self-improvement.",
            chapterText: "Sample chapter text about habit formation…",
            service: FakeOnDeviceAIService(availability: .available, delay: 0)
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Explainer — done (XXL text)") {
    HighlightExplainerSheet(
        model: HighlightExplainerModel(
            highlight: "Habits are the compound interest of self-improvement.",
            chapterText: "Sample chapter text about habit formation…",
            service: FakeOnDeviceAIService(availability: .available, delay: 0)
        )
    )
    .dynamicTypeSize(.accessibility3)
}

#Preview("Explainer — unavailable") {
    HighlightExplainerSheet(
        model: HighlightExplainerModel(
            highlight: "Habits are the compound interest of self-improvement.",
            chapterText: "Sample chapter text about habit formation…",
            service: FakeOnDeviceAIService(availability: .unavailableDeviceNotEligible)
        )
    )
}
#endif
