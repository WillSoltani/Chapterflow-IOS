import SwiftUI

/// A circular avatar that renders either provided initials or a person glyph,
/// on a calm accent-tinted background. (Remote image loading lives in a separate
/// `RemoteImage` component; this token component stays dependency-free.)
public struct Avatar: View {
    /// Standard avatar sizes.
    public enum Size: Sendable {
        case small
        case medium
        case large

        var diameter: CGFloat {
            switch self {
            case .small: 28
            case .medium: 40
            case .large: 64
            }
        }

        var textStyle: Font.TextStyle {
            switch self {
            case .small: .caption
            case .medium: .subheadline
            case .large: .title2
            }
        }
    }

    private let initials: String?
    private let size: Size

    public init(initials: String? = nil, size: Size = .medium) {
        self.initials = initials
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(DSColor.accent.opacity(0.16))
            .frame(width: size.diameter, height: size.diameter)
            .overlay(label)
            .overlay(Circle().strokeBorder(DSColor.accent.opacity(0.20), lineWidth: 1))
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var label: some View {
        if let initials, !initials.isEmpty {
            Text(initials.prefix(2).uppercased())
                .font(DSTypography.scaledFont(size.textStyle, weight: .semibold))
                .foregroundStyle(DSColor.accent)
        } else {
            Image(systemName: "person.fill")
                .font(DSTypography.scaledFont(size.textStyle))
                .foregroundStyle(DSColor.accent)
        }
    }

    private var accessibilityLabel: Text {
        if let initials, !initials.isEmpty {
            Text(verbatim: initials)
        } else {
            Text("Avatar")
        }
    }
}

#Preview("Avatar", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        HStack(spacing: DSSpacing.md) {
            Avatar(initials: "WS", size: .small)
            Avatar(initials: "RC", size: .medium)
            Avatar(size: .large)
        }
        .padding(DSSpacing.md)
    }
}
