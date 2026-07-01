import SwiftUI

/// A compact, circular icon-only button (e.g. toolbar / overlay controls).
///
/// Guarantees a 44-pt minimum tap target even though the visible glyph is
/// smaller, fires a selection haptic, and requires an accessibility label since
/// there is no visible text.
public struct IconButton: View {
    /// Visual treatment of the button's backdrop.
    public enum Style: Sendable {
        /// No fill — the glyph floats on the parent surface.
        case plain
        /// A quiet filled circle for controls that sit over content.
        case filled
    }

    private let systemName: String
    private let accessibilityLabel: LocalizedStringKey
    private let style: Style
    private let action: () -> Void

    public init(
        systemName: String,
        accessibilityLabel: LocalizedStringKey,
        style: Style = .plain,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(background)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .plain:
            Color.clear
        case .filled:
            Circle().fill(DSColor.surface)
        }
    }
}

#Preview("IconButton", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        HStack(spacing: DSSpacing.md) {
            IconButton(systemName: "heart", accessibilityLabel: "Save") {}
            IconButton(systemName: "textformat.size", accessibilityLabel: "Text size", style: .filled) {}
            IconButton(systemName: "ellipsis", accessibilityLabel: "More", style: .filled) {}
        }
        .padding(DSSpacing.md)
    }
}
