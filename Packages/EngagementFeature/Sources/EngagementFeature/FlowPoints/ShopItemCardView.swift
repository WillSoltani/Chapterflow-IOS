import SwiftUI
import DesignSystem
import Models

/// A single shop item displayed as a card with an action button.
struct ShopItemCardView: View {

    let item: ShopItem
    let action: ShopItemAction
    let onTap: () -> Void

    var body: some View {
        CFCard {
            HStack(spacing: .cfSpacing12) {
                itemIcon
                itemInfo
                Spacer(minLength: .cfSpacing8)
                actionButton
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Icon

    private var itemIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .cfRadius8)
                .fill(iconTint.opacity(0.12))
                .frame(width: 44, height: 44)
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 20))
                .foregroundStyle(iconTint)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Info

    private var itemInfo: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(item.name)
                .font(.cfBody.weight(.semibold))
                .foregroundStyle(Color.cfLabel)
                .lineLimit(1)
            Text(item.description)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if item.cost > 0 {
                costPill
            }
        }
    }

    private var costPill: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("\(item.cost) FP")
                .font(.cfCaption.weight(.medium))
        }
        .foregroundStyle(action == .buyDisabled ? Color.cfTertiaryLabel : Color.cfAccent)
        .padding(.horizontal, .cfSpacing8)
        .padding(.vertical, .cfSpacing2)
        .background(
            Capsule().fill(
                action == .buyDisabled
                    ? Color.cfSecondaryFill
                    : Color.cfAccent.opacity(0.1)
            )
        )
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch action {
        case .buy:
            Button(action: onTap) {
                Text("Buy")
                    .font(.cfCaption.weight(.semibold))
                    .padding(.horizontal, .cfSpacing12)
                    .padding(.vertical, .cfSpacing8)
                    .background(Color.cfAccent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Buy \(item.name)")

        case .buyDisabled:
            Text("Buy")
                .font(.cfCaption.weight(.semibold))
                .padding(.horizontal, .cfSpacing12)
                .padding(.vertical, .cfSpacing8)
                .background(Color.cfSecondaryFill)
                .foregroundStyle(Color.cfTertiaryLabel)
                .clipShape(Capsule())
                .accessibilityLabel("Not enough Flow Points to buy \(item.name)")

        case .equip:
            Button(action: onTap) {
                Text("Equip")
                    .font(.cfCaption.weight(.semibold))
                    .padding(.horizontal, .cfSpacing12)
                    .padding(.vertical, .cfSpacing8)
                    .background(Color.cfAccent.opacity(0.15))
                    .foregroundStyle(Color.cfAccent)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.cfAccent.opacity(0.4), lineWidth: 1))
            }
            .accessibilityLabel("Equip \(item.name)")

        case .equipped:
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("Equipped")
                    .font(.cfCaption.weight(.medium))
            }
            .padding(.horizontal, .cfSpacing12)
            .padding(.vertical, .cfSpacing8)
            .background(Color.green.opacity(0.1))
            .foregroundStyle(Color.green)
            .clipShape(Capsule())
            .accessibilityLabel("\(item.name) is currently equipped")

        case .owned:
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("Owned")
                    .font(.cfCaption.weight(.medium))
            }
            .padding(.horizontal, .cfSpacing12)
            .padding(.vertical, .cfSpacing8)
            .background(Color.cfSecondaryFill)
            .foregroundStyle(Color.cfSecondaryLabel)
            .clipShape(Capsule())
            .accessibilityLabel("\(item.name) already purchased")

        case .hidden:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var iconTint: Color {
        switch item.kind {
        case .bonusBookUnlock:  return .blue
        case .proPass7d:        return .yellow
        case .proPass30d:       return Color(red: 1, green: 0.75, blue: 0)
        case .theme:            return .purple
        case .frame:            return .teal
        case .seasonal:         return .pink
        case .unknown:          return Color.cfTertiaryLabel
        }
    }

    private var accessibilityDescription: String {
        let costText = item.cost > 0 ? ", costs \(item.cost) Flow Points" : ""
        switch action {
        case .buy:        return "\(item.name)\(costText). Tap to buy."
        case .buyDisabled: return "\(item.name)\(costText). Insufficient balance."
        case .equip:      return "\(item.name). Owned. Tap to equip."
        case .equipped:   return "\(item.name). Currently equipped."
        case .owned:      return "\(item.name). Already owned."
        case .hidden:     return "\(item.name)"
        }
    }
}

// MARK: - Preview

#Preview("Shop item cards") {
    let items: [(ShopItem, ShopItemAction)] = [
        (ShopItem(id: "1", kind: .bonusBookUnlock, name: "Bonus Book Unlock", description: "Add an extra book to your library", cost: 250, isOwned: false, isEquipped: nil, previewColor: nil), .buy),
        (ShopItem(id: "2", kind: .proPass7d, name: "7-Day Pro Pass", description: "All Pro features for 7 days", cost: 1_500, isOwned: false, isEquipped: nil, previewColor: nil), .buyDisabled),
        (ShopItem(id: "3", kind: .theme, name: "Midnight Blue", description: "Deep navy reader theme", cost: 500, isOwned: true, isEquipped: false, previewColor: "#1A3B6E"), .equip),
        (ShopItem(id: "4", kind: .frame, name: "Gold Frame", description: "Elegant gold profile border", cost: 300, isOwned: true, isEquipped: true, previewColor: nil), .equipped),
    ]
    return ScrollView {
        VStack(spacing: .cfSpacing12) {
            ForEach(items, id: \.0.id) { item, action in
                ShopItemCardView(item: item, action: action, onTap: {})
            }
        }
        .padding(.cfSpacing16)
    }
    .background(Color.cfGroupedBackground)
}
