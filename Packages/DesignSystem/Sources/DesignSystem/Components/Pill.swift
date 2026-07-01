import SwiftUI

/// A small capsule label ("tag" / "pill") for categories, states and metadata.
/// Tinted from a small semantic palette so meaning reads at a glance.
public struct Pill: View {
    /// The semantic tint of a pill.
    public enum Tint: Sendable {
        case neutral
        case accent
        case success
        case warning
        case danger

        var foreground: Color {
            switch self {
            case .neutral: DSColor.textSecondary
            case .accent: DSColor.accent
            case .success: DSColor.success
            case .warning: DSColor.warning
            case .danger: DSColor.danger
            }
        }

        var background: Color {
            switch self {
            case .neutral: DSColor.textSecondary.opacity(0.12)
            case .accent: DSColor.accent.opacity(0.14)
            case .success: DSColor.success.opacity(0.14)
            case .warning: DSColor.warning.opacity(0.16)
            case .danger: DSColor.danger.opacity(0.14)
            }
        }
    }

    private let title: LocalizedStringKey
    private let icon: String?
    private let tint: Tint

    public init(_ title: LocalizedStringKey, icon: String? = nil, tint: Tint = .neutral) {
        self.title = title
        self.icon = icon
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(DSTypography.caption.weight(.semibold))
        .foregroundStyle(tint.foreground)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(tint.background, in: Capsule())
    }
}

#Preview("Pill", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        VStack(spacing: DSSpacing.sm) {
            Pill("New", tint: .accent)
            Pill("Completed", icon: "checkmark", tint: .success)
            Pill("Due", icon: "clock", tint: .warning)
            Pill("Locked", icon: "lock", tint: .neutral)
        }
        .padding(DSSpacing.md)
    }
}
