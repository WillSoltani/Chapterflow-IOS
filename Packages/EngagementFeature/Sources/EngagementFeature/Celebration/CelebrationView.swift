import SwiftUI
import DesignSystem

#if canImport(UIKit)
import UIKit
#endif

// MARK: - CelebrationView

/// A full-screen overlay that presents the current event in the sequence.
///
/// Mount this once at the top of the view hierarchy and pass a shared
/// ``CelebrationPresenter``. The view observes the presenter and shows/hides
/// itself automatically.
///
/// ```swift
/// ContentView()
///     .overlay {
///         CelebrationView(presenter: sharedPresenter)
///     }
/// ```
public struct CelebrationView: View {

    let presenter: CelebrationPresenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(presenter: CelebrationPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if let event = presenter.currentEvent {
            ZStack {
                // Dimmed backdrop — tap to advance.
                Color.black
                    .opacity(0.45)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .onTapGesture { presenter.advance() }

                // Confetti — suppressed when Reduce Motion is on.
                if !reduceMotion && event.wantsConfetti {
                    CFConfetti(isActive: true)
                }

                // Card — always centred.
                CelebrationCardView(event: event)
                    .padding(.horizontal, .cfSpacing24)
                    .onTapGesture { presenter.advance() }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                                removal:   .opacity.combined(with: .scale(scale: 1.04))
                            )
                    )
                    .id(event.headline) // force re-render on each new event
            }
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.4, dampingFraction: 0.8),
                value: event.headline
            )
            .onAppear { triggerHaptic(for: event) }
            .accessibilityAddTraits(.isModal)
        }
    }

    // MARK: Haptics

    private func triggerHaptic(for event: CelebrationEvent) {
#if canImport(UIKit)
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch event {
        case .loopComplete, .tierUp, .streakMilestone, .badgeEarned, .journeyComplete:
            style = .heavy
        case .streakIncrement:
            style = .medium
        case .flowPointsGained, .insightSpark:
            style = .light
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

// MARK: - View modifier convenience

public extension View {
    /// Overlays a ``CelebrationView`` driven by the given presenter.
    ///
    /// Call this once near the root of the feature's view hierarchy so the
    /// overlay spans the full screen.
    func celebrationOverlay(_ presenter: CelebrationPresenter) -> some View {
        overlay { CelebrationView(presenter: presenter) }
    }
}
