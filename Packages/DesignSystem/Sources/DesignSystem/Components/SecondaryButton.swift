import SwiftUI

/// The secondary button: a tinted, bordered accent button for lower-emphasis
/// actions. Same press feedback, haptics, Dynamic Type and 44-pt tap target as
/// ``PrimaryButton``.
public struct SecondaryButton: View {
    private let title: LocalizedStringKey
    private let icon: String?
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(DSTypography.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, DSSpacing.sm)
            .padding(.horizontal, DSSpacing.md)
            .foregroundStyle(DSColor.accent)
            .background(DSColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .strokeBorder(DSColor.accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("SecondaryButton", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        VStack(spacing: DSSpacing.md) {
            SecondaryButton("Add to Library", icon: "plus") {}
            SecondaryButton("Disabled") {}
                .disabled(true)
        }
        .padding(DSSpacing.md)
    }
}
