import SwiftUI

/// The visual overlay that renders the current toast at the bottom of the shell.
///
/// Applied once at the root via ``SwiftUI/View/toastLayer(_:)``. Respects Reduce
/// Motion (falls back to an opacity fade) and exposes the toast to VoiceOver.
struct ToastLayer: ViewModifier {
    let presenter: ToastPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = presenter.current {
                    toastView(toast)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(transition)
                        .id(toast.id)
                }
            }
            .animation(reduceMotion ? .easeInOut : .spring(duration: 0.35), value: presenter.current)
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private func toastView(_ toast: Toast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.systemImage)
                .foregroundStyle(toast.style.tint)
            Text(toast.message)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
        .onTapGesture { presenter.dismiss() }
    }
}

public extension View {
    /// Installs the toast overlay for `presenter`. Apply once, at the root.
    func toastLayer(_ presenter: ToastPresenter) -> some View {
        modifier(ToastLayer(presenter: presenter))
    }
}
