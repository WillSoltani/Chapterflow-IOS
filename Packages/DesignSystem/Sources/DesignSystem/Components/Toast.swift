import SwiftUI

/// The semantic style of a ``Toast``.
public enum ToastStyle: Sendable {
    case info
    case success
    case warning
    case danger

    var tint: Color {
        switch self {
        case .info: DSColor.accent
        case .success: DSColor.success
        case .warning: DSColor.warning
        case .danger: DSColor.danger
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }
}

/// A transient toast payload. Identity drives presentation, so pushing a new
/// value replaces the current toast.
///
/// Not `Sendable`: `LocalizedStringKey` is not `Sendable`, and toasts are only
/// ever created and presented on the main actor.
public struct ToastData: Identifiable, Equatable {
    public let id = UUID()
    public let style: ToastStyle
    public let message: LocalizedStringKey

    public init(style: ToastStyle, message: LocalizedStringKey) {
        self.style = style
        self.message = message
    }

    public static func == (lhs: ToastData, rhs: ToastData) -> Bool { lhs.id == rhs.id }
}

/// The toast surface — an elevated capsule with a status glyph and message.
public struct Toast: View {
    private let data: ToastData

    public init(_ data: ToastData) {
        self.data = data
    }

    public var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: data.style.systemImage)
                .foregroundStyle(data.style.tint)
            Text(data.message)
                .font(DSTypography.subheadline.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(DSColor.surfaceElevated, in: Capsule())
        .dsShadow(.elevated)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Presenter

public extension View {
    /// Presents a transient toast at the top of the screen. The toast
    /// auto-dismisses after `duration` seconds; setting the binding to `nil`
    /// dismisses immediately. Entry/exit is gated by Reduce Motion.
    func toast(_ item: Binding<ToastData?>, duration: Double = 2.5) -> some View {
        modifier(ToastPresenter(item: item, duration: duration))
    }
}

private struct ToastPresenter: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var item: ToastData?
    let duration: Double

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let item {
                Toast(item)
                    .padding(.top, DSSpacing.sm)
                    .transition(reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity))
                    .id(item.id)
                    .task(id: item.id) {
                        try? await Task.sleep(for: .seconds(duration))
                        withAnimation(DSMotion.gated(DSMotion.spring, reduceMotion: reduceMotion)) {
                            self.item = nil
                        }
                    }
            }
        }
        .animation(DSMotion.gated(DSMotion.spring, reduceMotion: reduceMotion), value: item)
    }
}

#Preview("Toast", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        VStack(spacing: DSSpacing.sm) {
            Toast(ToastData(style: .success, message: "Saved to library"))
            Toast(ToastData(style: .warning, message: "You're offline"))
            Toast(ToastData(style: .danger, message: "Couldn't load chapter"))
        }
        .padding(DSSpacing.md)
    }
}
