import SwiftUI
import DesignSystem
import Models
import CoreKit

/// A confirmation sheet shown before a flow-points redeem or equip action.
///
/// Call `onConfirm` / `onCancel` when the user taps the corresponding button.
/// The caller is responsible for dismissal.
struct RedeemConfirmationSheet: View {

    let item: ShopItem
    let currentBalance: Int
    let isRedeeming: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var isEquip: Bool { item.kind.isCosmetic && (item.isOwned ?? false) }
    private var balanceAfter: Int { currentBalance - item.cost }
    private var canAfford: Bool { currentBalance >= item.cost }

    var body: some View {
        NavigationStack {
            VStack(spacing: .cfSpacing24) {
                iconSection
                detailSection
                if !isEquip { costSection }
                Spacer()
                actionButtons
            }
            .padding(.cfSpacing24)
            .navigationTitle(isEquip ? "Equip Item" : "Confirm Purchase")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isRedeeming)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Icon

    private var iconSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .cfRadius20)
                .fill(iconBackgroundColor.opacity(0.15))
                .frame(width: 80, height: 80)
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 36))
                .foregroundStyle(iconBackgroundColor)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Name + description

    private var detailSection: some View {
        VStack(spacing: .cfSpacing8) {
            Text(item.name)
                .font(.cfTitle3.weight(.semibold))
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)
            Text(item.description)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Cost breakdown (buy only)

    private var costSection: some View {
        CFCard {
            VStack(spacing: .cfSpacing12) {
                row(label: "Cost", value: "\(item.cost) FP", color: .cfLabel)
                Divider()
                row(label: "Your balance", value: "\(currentBalance) FP", color: .cfLabel)
                Divider()
                row(
                    label: "Balance after",
                    value: "\(balanceAfter) FP",
                    color: canAfford ? Color.green : .red
                )
            }
        }
    }

    private func row(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
            Spacer()
            Text(value)
                .font(.cfBody.weight(.medium))
                .foregroundStyle(color)
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: .cfSpacing12) {
            Button(action: onConfirm) {
                HStack(spacing: .cfSpacing8) {
                    if isRedeeming {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                    Text(isEquip ? "Equip" : "Buy Now")
                        .font(.cfBody.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.cfSpacing16)
                .background(Color.cfAccent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
            }
            .disabled(isRedeeming || (!isEquip && !canAfford))
            .accessibilityLabel(isEquip ? "Equip \(item.name)" : "Buy \(item.name) for \(item.cost) flow points")

            if !isEquip && !canAfford {
                insufficientBalanceLabel
            }
        }
    }

    private var insufficientBalanceLabel: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "exclamationmark.circle")
                .font(.cfCaption)
            Text("Not enough Flow Points")
                .font(.cfCaption)
        }
        .foregroundStyle(Color.cfSecondaryLabel)
        .accessibilityLabel("Insufficient balance. You need \(item.cost - currentBalance) more Flow Points.")
    }

    // MARK: - Helpers

    private var iconBackgroundColor: Color {
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
}

// MARK: - Preview

#Preview("Redeem — buy (affordable)") {
    RedeemConfirmationSheet(
        item: ShopItem(
            id: "item-1",
            kind: .bonusBookUnlock,
            name: "Bonus Book Unlock",
            description: "Unlock one additional book slot beyond your free tier.",
            cost: 250,
            isOwned: false,
            isEquipped: nil,
            previewColor: nil
        ),
        currentBalance: 1_250,
        isRedeeming: false,
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Redeem — buy (insufficient)") {
    RedeemConfirmationSheet(
        item: ShopItem(
            id: "item-2",
            kind: .proPass30d,
            name: "30-Day Pro Pass",
            description: "Unlock all Pro features for 30 days.",
            cost: 2_000,
            isOwned: false,
            isEquipped: nil,
            previewColor: nil
        ),
        currentBalance: 500,
        isRedeeming: false,
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Redeem — equip cosmetic") {
    RedeemConfirmationSheet(
        item: ShopItem(
            id: "theme-1",
            kind: .theme,
            name: "Midnight Blue",
            description: "A deep navy reader theme for late-night sessions.",
            cost: 0,
            isOwned: true,
            isEquipped: false,
            previewColor: "#1A3B6E"
        ),
        currentBalance: 800,
        isRedeeming: false,
        onConfirm: {},
        onCancel: {}
    )
}
