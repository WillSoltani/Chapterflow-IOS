import Foundation
import Observation
import CoreKit
#if canImport(UIKit)
import UIKit
import SwiftUI

// MARK: - Model

/// Observable model that drives the share-card flow.
///
/// Usage:
/// 1. Construct with a ``ShareCardInput`` and the shared ``SocialRepository``.
/// 2. Call ``prepareAndShare()`` from the share button's action.
/// 3. Observe ``phase`` for loading/error feedback.
/// 4. Bind the sheet to ``shareItems`` — when non-nil, present an
///    `ActivityViewControllerRepresentable` (or ``ShareSheet``).
@Observable
@MainActor
public final class ShareCardModel {

    // MARK: Phase

    public enum Phase: Equatable {
        case idle
        case rendering
        case ready
        case error(String)
    }

    // MARK: State

    public private(set) var phase: Phase = .idle
    /// The rendered UIImage ready for sharing. Set after ``prepareAndShare()`` succeeds.
    public private(set) var shareItems: [Any]?

    // MARK: Dependencies

    private let input: ShareCardInput
    private let repository: any SocialRepository
    private let scale: CGFloat

    // MARK: Init

    /// - Parameters:
    ///   - input: The card content to render.
    ///   - repository: The SocialRepository used to post the share event.
    ///   - scale: Render scale. Default 3.0 for crisp 1125×1125 px output.
    public init(
        input: ShareCardInput,
        repository: any SocialRepository,
        scale: CGFloat = 3.0
    ) {
        self.input = input
        self.repository = repository
        self.scale = scale
    }

    // MARK: Actions

    /// Renders the share card to a UIImage, stores it in ``shareItems``, and
    /// posts the share event to the server. Safe to call multiple times.
    public func prepareAndShare() async {
        guard phase != .rendering else { return }
        phase = .rendering

        let rendered = renderImage()
        guard let image = rendered else {
            phase = .error("Could not render share card.")
            return
        }

        shareItems = [image]
        phase = .ready

        // Fire-and-forget: a dropped analytics event is not fatal.
        Task {
            try? await repository.postShareEvent(
                cardType: input.cardType,
                destination: .other
            )
        }
    }

    /// Resets to idle so the share flow can be triggered again.
    public func reset() {
        phase = .idle
        shareItems = nil
    }

    // MARK: Rendering

    private func renderImage() -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(input: input))
        renderer.scale = scale
        return renderer.uiImage
    }
}

// MARK: - Share sheet UIKit wrapper

/// A `UIViewControllerRepresentable` that presents `UIActivityViewController`
/// and dismisses when the user finishes sharing.
public struct ShareSheet: UIViewControllerRepresentable {
    public let items: [Any]
    public var onComplete: ((UIActivityType?, Bool) -> Void)?

    public init(items: [Any], onComplete: ((UIActivityType?, Bool) -> Void)? = nil) {
        self.items = items
        self.onComplete = onComplete
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            onComplete?(activityType, completed)
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - ShareCardButton convenience view

/// A plug-and-play share button that renders the card and presents the share
/// sheet. Drop it anywhere a share action is needed — no model wiring required.
///
/// ```swift
/// ShareCardButton(input: .streak(days: 14, userName: "Alice", tier: .analyst, referralCode: nil),
///                 repository: socialRepository) {
///     Label("Share streak", systemImage: "square.and.arrow.up")
/// }
/// ```
public struct ShareCardButton<Label: View>: View {
    @State private var model: ShareCardModel
    @State private var isPresenting = false
    private let label: Label

    public init(
        input: ShareCardInput,
        repository: any SocialRepository,
        @ViewBuilder label: () -> Label
    ) {
        self._model = State(initialValue: ShareCardModel(input: input, repository: repository))
        self.label = label()
    }

    public var body: some View {
        Button {
            Task { await triggerShare() }
        } label: {
            label
        }
        .disabled(model.phase == .rendering)
        .sheet(isPresented: $isPresenting, onDismiss: { model.reset() }) {
            if let items = model.shareItems {
                ShareSheet(items: items)
                    .presentationDetents([.medium, .large])
            }
        }
        .onChange(of: model.phase) { _, newPhase in
            if newPhase == .ready {
                isPresenting = true
            }
        }
        .accessibilityLabel("Share")
    }

    private func triggerShare() async {
        await model.prepareAndShare()
    }
}

#endif
