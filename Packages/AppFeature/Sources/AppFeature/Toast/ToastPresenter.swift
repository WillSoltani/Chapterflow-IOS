import SwiftUI
import Observation

/// A transient, non-blocking message shown over the shell.
///
/// > Placeholder styling: **DesignSystem (P0.2)** ships the canonical `Toast`
/// > component (tokens, haptics, motion). This local model + presenter give the
/// > root a working toast surface now; when P0.2 lands, re-skin ``ToastLayer``
/// > with the DesignSystem component while keeping ``ToastPresenter`` as the
/// > root-level coordinator.
public struct Toast: Identifiable, Equatable, Sendable {
    public enum Style: Sendable {
        case info, success, warning, error

        var systemImage: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: return .accentColor
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    public let id = UUID()
    public let message: String
    public let style: Style

    public init(_ message: String, style: Style = .info) {
        self.message = message
        self.style = style
    }
}

/// Root-level coordinator that presents one toast at a time and auto-dismisses.
///
/// Injected into the environment at the root so any feature can surface a toast
/// with `@Environment(ToastPresenter.self)`.
@MainActor
@Observable
public final class ToastPresenter {
    /// The toast currently on screen, if any.
    public private(set) var current: Toast?

    private var dismissTask: Task<Void, Never>?

    public init() {}

    /// Shows a toast, replacing any current one, and schedules auto-dismiss.
    public func show(_ toast: Toast, duration: Duration = .seconds(3)) {
        dismissTask?.cancel()
        current = toast
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// Convenience for the common message + style call.
    public func show(_ message: String, style: Toast.Style = .info) {
        show(Toast(message, style: style))
    }

    /// Dismisses the current toast immediately.
    public func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}
