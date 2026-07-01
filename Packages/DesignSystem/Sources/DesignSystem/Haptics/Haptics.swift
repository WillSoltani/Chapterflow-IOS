import UIKit

/// Thin wrapper over `UIFeedbackGenerator` for consistent, tasteful haptics.
///
/// All entry points are `@MainActor` because the underlying generators must be
/// used from the main thread. Generators are created per-call (cheap) and left
/// for the system to manage; for latency-critical repeated feedback a caller can
/// hold and `prepare()` its own generator.
@MainActor
public enum Haptics {
    /// A light impact — the standard "something happened" tap for buttons.
    public static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A success notification — task completed, quiz passed, purchase restored.
    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A warning notification — a recoverable problem or caution.
    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// A selection change — moving between segments, pickers, options.
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
