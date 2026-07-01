import SwiftUI

/// Motion tokens — a small, consistent set of durations and springs.
///
/// **Reduce Motion.** Every animation the design system applies must pass
/// through ``gated(_:reduceMotion:)`` (or the ``SwiftUI/View/dsAnimation(_:value:)``
/// modifier) so that, when the user has Reduce Motion enabled, transitions
/// collapse to an instantaneous state change rather than moving or scaling.
public enum DSMotion {
    // MARK: Durations (seconds)

    /// 0.18s — micro-interactions (press, toggles).
    public static let quick: Double = 0.18
    /// 0.28s — the default UI transition.
    public static let standard: Double = 0.28
    /// 0.45s — larger, more deliberate transitions.
    public static let slow: Double = 0.45

    // MARK: Curves

    /// The default easing curve.
    public static let standardEase = Animation.easeInOut(duration: standard)
    /// A calm, low-bounce spring for most content movement.
    public static let spring = Animation.spring(response: 0.4, dampingFraction: 0.85)
    /// A snappier spring for small controls (button press, selection).
    public static let snappySpring = Animation.spring(response: 0.28, dampingFraction: 0.8)

    // MARK: Reduce Motion gating

    /// Returns the animation, or `nil` when Reduce Motion is enabled.
    ///
    /// Passing `nil` to a SwiftUI `.animation(_:value:)` (or `withAnimation`)
    /// performs the state change without animating.
    public static func gated(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

public extension View {
    /// Applies an animation that is automatically disabled under Reduce Motion.
    ///
    /// Reads `\.accessibilityReduceMotion` from the environment, so callers do
    /// not have to thread the flag through manually.
    func dsAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(DSMotion.gated(animation, reduceMotion: reduceMotion), value: value)
    }
}
