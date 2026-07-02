import SwiftUI
import DesignSystem

/// A compact glanceable stat card used in the 2×2 dashboard grid.
struct StatCardView: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let iconColor: Color

    var body: some View {
        CFCard {
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                HStack {
                    Image(systemName: icon)
                        .font(.cfSubheadline)
                        .foregroundStyle(iconColor)
                    Spacer()
                }
                Text(value)
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(title)
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfTertiaryLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(subtitle)")
    }
}

// MARK: - Preview

#Preview("StatCards") {
    LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())],
        spacing: .cfSpacing12
    ) {
        StatCardView(title: "Streak", value: "14", subtitle: "days", icon: "flame.fill", iconColor: .orange)
        StatCardView(title: "Books", value: "7", subtitle: "completed", icon: "books.vertical.fill", iconColor: Color.cfAccent)
        StatCardView(title: "Tier", value: "Analyst", subtitle: "", icon: "star.fill", iconColor: .yellow)
        StatCardView(title: "Flow Points", value: "1,250", subtitle: "points", icon: "bolt.fill", iconColor: .purple)
    }
    .padding(.cfSpacing16)
    .background(Color.cfGroupedBackground)
}
