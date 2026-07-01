import SwiftUI

/// The primary call-to-action button: a filled, full-width accent button with a
/// pressed-state scale, haptic tap, optional leading icon, and a loading state.
///
/// Fully Dynamic-Type driven and guaranteed a 44-pt minimum tap target.
public struct PrimaryButton: View {
    private let title: LocalizedStringKey
    private let icon: String?
    private let isLoading: Bool
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DSColor.onAccent)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(DSTypography.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, DSSpacing.sm)
            .padding(.horizontal, DSSpacing.md)
            .foregroundStyle(DSColor.onAccent)
            .background(DSColor.accent, in: RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("PrimaryButton", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        VStack(spacing: DSSpacing.md) {
            PrimaryButton("Continue Reading", icon: "book") {}
            PrimaryButton("Loading", isLoading: true) {}
            PrimaryButton("Disabled") {}
                .disabled(true)
        }
        .padding(DSSpacing.md)
    }
}
