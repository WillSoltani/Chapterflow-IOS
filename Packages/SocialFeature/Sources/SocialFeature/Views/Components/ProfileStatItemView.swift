import SwiftUI
import DesignSystem

/// A single stat card shown in the profile stats grid (streak, books, points).
public struct ProfileStatItemView: View {

    private let icon: String
    private let value: String
    private let label: String

    public init(icon: String, value: String, label: String) {
        self.icon = icon
        self.value = value
        self.label = label
    }

    public var body: some View {
        VStack(spacing: .cfSpacing4) {
            Text(icon)
                .font(.system(size: 22))
            Text(value)
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
                .contentTransition(.numericText())
            Text(label)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .cfSpacing12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ProfileStatItemView") {
    HStack(spacing: .cfSpacing8) {
        ProfileStatItemView(icon: "🔥", value: "14", label: "Streak")
        ProfileStatItemView(icon: "📚", value: "7", label: "Books")
        ProfileStatItemView(icon: "⚡", value: "4.2k", label: "Points")
    }
    .padding(.cfSpacing16)
    .background(Color.cfGroupedBackground)
}
#endif
