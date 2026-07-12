import SwiftUI
import DesignSystem

// MARK: - ProductOptionRow

struct ProductOptionRow: View {
    let info: StoreProductInfo
    let isSelected: Bool
    let savingsPercent: Int?
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    verticalLayout
                } else {
                    ViewThatFits(in: .horizontal) {
                        horizontalLayout
                        verticalLayout
                    }
                }
            }
            .padding(.cfSpacing16)
            .background(
                RoundedRectangle(cornerRadius: .cfRadius16)
                    .fill(Color.cfSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: .cfRadius16)
                            .strokeBorder(
                                isSelected ? Color.cfAccent : Color.clear,
                                lineWidth: .cfSpacing2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Select this subscription plan")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    var accessibilityDescription: String {
        var parts = [
            info.displayName,
            "\(info.displayPrice) per \(info.periodLabel)"
        ]
        if let introductoryOfferText = info.introductoryOfferText {
            parts.append(introductoryOfferText)
            parts.append(
                "then \(info.displayPrice) per \(info.periodLabel), renews automatically until canceled"
            )
        } else {
            parts.append("renews automatically until canceled")
        }
        if info.isPopular {
            parts.append("popular")
        }
        if let savingsPercent, savingsPercent > 0 {
            parts.append("save \(savingsPercent) percent")
        }
        return parts.joined(separator: ", ")
    }

    private var horizontalLayout: some View {
        HStack(spacing: .cfSpacing12) {
            selectionIndicator
            planDetails
            Spacer(minLength: .cfSpacing8)
            VStack(alignment: .trailing, spacing: .cfSpacing2) {
                Text(info.displayPrice)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                Text("/ \(info.periodLabel)")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            HStack(alignment: .top, spacing: .cfSpacing12) {
                selectionIndicator
                planDetails
            }
            Text("\(info.displayPrice) per \(info.periodLabel)")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.cfAccent : Color.cfTertiaryLabel)
            .font(.title3)
            .accessibilityHidden(true)
    }

    private var planDetails: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(info.displayName)
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            planBadges
            if let intro = info.introductoryOfferText {
                Text(intro)
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfAccent)
            }
        }
    }

    @ViewBuilder
    private var planBadges: some View {
        if info.isPopular || hasSavings {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: .cfSpacing8) {
                    badgeContents
                }
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    badgeContents
                }
            }
        }
    }

    private var hasSavings: Bool {
        (savingsPercent ?? 0) > 0
    }

    @ViewBuilder
    private var badgeContents: some View {
        if info.isPopular {
            Text("Popular")
                .font(.cfCaption2)
                .foregroundStyle(.white)
                .padding(.horizontal, .cfSpacing8)
                .padding(.vertical, .cfSpacing2)
                .background(Color.cfAccent, in: Capsule())
        }
        if let savingsPercent, savingsPercent > 0 {
            Text("Save \(savingsPercent)%")
                .font(.cfCaption2)
                .foregroundStyle(Color.cfAccent)
                .padding(.horizontal, .cfSpacing8)
                .padding(.vertical, .cfSpacing2)
                .background(Color.cfAccent.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - ProBenefit

enum ProBenefit: CaseIterable {
    case unlimitedBooks, offlineReading, aiInsights, quizzes, notes

    var iconName: String {
        switch self {
        case .unlimitedBooks:  return "books.vertical.fill"
        case .offlineReading:  return "arrow.down.circle.fill"
        case .aiInsights:      return "sparkles"
        case .quizzes:         return "checkmark.circle.fill"
        case .notes:           return "pencil.and.outline"
        }
    }

    var title: String {
        switch self {
        case .unlimitedBooks:  return "Unlimited Books"
        case .offlineReading:  return "Offline Reading"
        case .aiInsights:      return "AI Deep Dive"
        case .quizzes:         return "Spaced-Repetition Quizzes"
        case .notes:           return "Highlights & Notes"
        }
    }

    var subtitle: String {
        switch self {
        case .unlimitedBooks:  return "Access our full catalogue of titles"
        case .offlineReading:  return "Read anywhere — no internet required"
        case .aiInsights:      return "Ask anything about any book"
        case .quizzes:         return "Retain what you read, long-term"
        case .notes:           return "Capture insights and export them"
        }
    }
}
