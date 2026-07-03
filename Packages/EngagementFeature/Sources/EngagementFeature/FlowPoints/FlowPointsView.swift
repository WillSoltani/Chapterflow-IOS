import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - FlowPointsView

/// The Flow-Points economy screen.
///
/// Shows the user's balance, a transaction ledger, and the shop catalogue
/// with buy / equip actions. Redemptions are always server-authoritative.
public struct FlowPointsView: View {

    private let model: FlowPointsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: FlowPointsModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                FlowPointsSkeletonView()
            case .loaded:
                loadedView
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle("Flow Points")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .task { model.load() }
        .refreshable { await model.refresh() }
        .sheet(item: Binding(
            get: { model.pendingItem },
            set: { if $0 == nil { model.dismissConfirmation() } }
        )) { item in
            RedeemConfirmationSheet(
                item: item,
                currentBalance: model.balance,
                isRedeeming: model.isRedeeming,
                onConfirm: { model.confirm() },
                onCancel: { model.dismissConfirmation() }
            )
        }
        .alert(
            "Redemption Failed",
            isPresented: Binding(
                get: { model.redeemError != nil },
                set: { if !$0 { /* error clears on next attempt */ } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = model.redeemError {
                Text(error.errorDescription ?? "Something went wrong. Please try again.")
            }
        }
    }

    // MARK: - Loaded

    private var loadedView: some View {
        ScrollView {
            VStack(spacing: .cfSpacing20) {
                balanceHero
                tabPicker
                switch model.selectedTab {
                case .ledger:
                    ledgerSection
                case .shop:
                    shopSection
                }
            }
            .padding(.cfSpacing16)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.selectedTab)
        }
    }

    // MARK: - Balance hero

    private var balanceHero: some View {
        CFCard {
            HStack(alignment: .center, spacing: .cfSpacing16) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.cfAccent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("\(model.balance)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.cfLabel)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: model.balance)
                    Text("Flow Points")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }

                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Balance: \(model.balance) Flow Points")
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("View", selection: Binding(
            get: { model.selectedTab },
            set: { model.selectedTab = $0 }
        )) {
            Text("Ledger").tag(FlowPointsModel.Tab.ledger)
            Text("Shop").tag(FlowPointsModel.Tab.shop)
        }
        .pickerStyle(.segmented)
        .onChange(of: model.selectedTab) { _, newTab in
            if newTab == .shop { model.loadShopIfNeeded() }
        }
    }

    // MARK: - Ledger

    @ViewBuilder
    private var ledgerSection: some View {
        if model.ledger.isEmpty {
            emptyLedger
        } else {
            VStack(spacing: 0) {
                CFCard {
                    VStack(spacing: 0) {
                        ForEach(model.ledger.reversed()) { entry in
                            LedgerRowView(entry: entry)
                            if entry.id != model.ledger.first?.id {
                                Divider()
                                    .padding(.leading, .cfSpacing48 + .cfSpacing8)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyLedger: some View {
        CFEmptyState(
            systemImage: "bolt.slash",
            title: "No Transactions Yet",
            description: "Flow Points appear here as you read, quiz, and hit milestones."
        )
        .padding(.top, .cfSpacing32)
    }

    // MARK: - Shop

    @ViewBuilder
    private var shopSection: some View {
        switch model.shopLoadState {
        case .idle, .loading:
            ShopSkeletonView()
        case .loaded:
            shopContent
        case .error(let error):
            shopErrorView(error)
        }
    }

    private var shopContent: some View {
        VStack(spacing: .cfSpacing24) {
            if !model.shopRewards.isEmpty {
                shopSectionGroup(
                    header: "Rewards",
                    icon: "gift.fill",
                    items: model.shopRewards
                )
            }
            if !model.shopCosmetics.isEmpty {
                shopSectionGroup(
                    header: "Cosmetics",
                    icon: "paintpalette.fill",
                    items: model.shopCosmetics
                )
            }
            if model.shopRewards.isEmpty && model.shopCosmetics.isEmpty {
                CFEmptyState(
                    systemImage: "storefront",
                    title: "Shop is Empty",
                    description: "New items will appear here when they become available."
                )
                .padding(.top, .cfSpacing32)
            }
        }
    }

    private func shopSectionGroup(header: String, icon: String, items: [ShopItem]) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label(header, systemImage: icon)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            VStack(spacing: .cfSpacing8) {
                ForEach(items) { item in
                    let itemAction = model.action(for: item)
                    if itemAction != .hidden {
                        ShopItemCardView(
                            item: item,
                            action: itemAction,
                            onTap: { model.showConfirmation(for: item) }
                        )
                    }
                }
            }
        }
    }

    private func shopErrorView(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "storefront")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfTertiaryLabel)
            Text("Couldn't load the shop.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
            Button("Try Again") { model.loadShopIfNeeded() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, .cfSpacing32)
    }

    // MARK: - Error state

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing16) {
            Spacer()
            Image(systemName: "bolt.slash")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfTertiaryLabel)
            Text(error.errorDescription ?? "Couldn't load Flow Points.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try Again") { model.load() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(.cfSpacing24)
    }
}

// MARK: - LedgerRowView

private struct LedgerRowView: View {

    let entry: FlowLedgerEntry

    var body: some View {
        HStack(spacing: .cfSpacing12) {
            iconView
            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(entry.description)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                    .lineLimit(2)
                Text(formattedDate)
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
            Spacer()
            amountView
        }
        .padding(.vertical, .cfSpacing12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(iconTint.opacity(0.12))
                .frame(width: 36, height: 36)
            Image(systemName: entry.type.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(iconTint)
        }
        .accessibilityHidden(true)
    }

    private var amountView: some View {
        let isEarning = entry.amount >= 0
        return Text(isEarning ? "+\(entry.amount)" : "\(entry.amount)")
            .font(.cfBody.weight(.semibold))
            .foregroundStyle(isEarning ? Color.green : Color.cfLabel)
    }

    private var iconTint: Color {
        switch entry.type {
        case .earnDaily, .earnStreak, .earnMilestone, .earnQuiz: return Color.green
        case .redeem:       return Color.cfAccent
        case .adjustment:   return Color.orange
        case .unknown:      return Color.cfTertiaryLabel
        }
    }

    private var formattedDate: String {
        guard let date = ISO8601DateFormatter().date(from: entry.createdAt) else {
            return entry.createdAt
        }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }

    private var accessibilityLabel: String {
        let sign = entry.amount >= 0 ? "earned" : "spent"
        return "\(entry.description). \(sign) \(abs(entry.amount)) Flow Points. \(formattedDate)."
    }
}

// MARK: - Skeletons

private struct FlowPointsSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: .cfSpacing20) {
                CFCard { CFSkeleton().frame(height: 80) }
                CFSkeleton().frame(height: 32).clipShape(RoundedRectangle(cornerRadius: .cfRadius8))
                CFCard { CFSkeleton().frame(height: 240) }
            }
            .padding(.cfSpacing16)
        }
    }
}

private struct ShopSkeletonView: View {
    var body: some View {
        VStack(spacing: .cfSpacing12) {
            ForEach(0..<4, id: \.self) { _ in
                CFCard { CFSkeleton().frame(height: 72) }
            }
        }
    }
}

// MARK: - Previews

#Preview("Flow Points — light") {
    NavigationStack {
        FlowPointsView(model: .preview)
    }
}

#Preview("Flow Points — dark") {
    NavigationStack {
        FlowPointsView(model: .preview)
    }
    .preferredColorScheme(.dark)
}

#Preview("Flow Points — XXL text") {
    NavigationStack {
        FlowPointsView(model: .preview)
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Flow Points — empty ledger") {
    NavigationStack {
        FlowPointsView(model: .previewEmpty)
    }
}

#Preview("Flow Points — shop tab") {
    NavigationStack {
        FlowPointsView(model: .previewShop)
    }
}
