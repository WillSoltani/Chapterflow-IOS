import SwiftUI

/// A `ButtonStyle` that adds a subtle pressed-state scale, gated by Reduce
/// Motion. Shared by the design-system buttons so press feedback is uniform.
public struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    private let pressedScale: CGFloat

    public init(pressedScale: CGFloat = 0.97) {
        self.pressedScale = pressedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(DSMotion.gated(DSMotion.snappySpring, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
