import SwiftUI
import DesignSystem

/// The Settings tab.
///
/// Shows the user's current subscription plan, upgrade or manage-subscription
/// options, and general app preferences. Keeps subscription upgrade prompts
/// non-intrusive — they are informational rows, not modal banners.
///
/// All subscription state is injected from `AppFeature` via `EntitlementService`;
/// SettingsFeature itself has no StoreKit dependency.
public struct SettingsView: View {

    private let isPro: Bool
    private let remainingFreeStarts: Int
    private let currentPeriodEnd: Date?
    private let cancelAtPeriodEnd: Bool?
    private let onShowPaywall: (() -> Void)?
    private let onManageSubscription: (() -> Void)?

    public init(
        isPro: Bool = false,
        remainingFreeStarts: Int = 0,
        currentPeriodEnd: Date? = nil,
        cancelAtPeriodEnd: Bool? = nil,
        onShowPaywall: (() -> Void)? = nil,
        onManageSubscription: (() -> Void)? = nil
    ) {
        self.isPro = isPro
        self.remainingFreeStarts = remainingFreeStarts
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
        self.onShowPaywall = onShowPaywall
        self.onManageSubscription = onManageSubscription
    }

    public var body: some View {
        NavigationStack {
            Form {
                subscriptionSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    // MARK: - Subscription section

    private var subscriptionSection: some View {
        Section("Subscription") {
            planRow

            if isPro {
                periodEndRow
                manageSubscriptionRow
            } else {
                if remainingFreeStarts > 0 {
                    freeStartsRow
                }
                upgradeRow
            }
        }
    }

    private var planRow: some View {
        HStack {
            Text("Plan")
                .foregroundStyle(Color.cfLabel)
            Spacer()
            Text(isPro ? "Pro" : "Free")
                .font(.cfSubheadline.weight(isPro ? .semibold : .regular))
                .foregroundStyle(isPro ? Color.cfAccent : Color.cfSecondaryLabel)
                .padding(.horizontal, .cfSpacing8)
                .padding(.vertical, 3)
                .background(Capsule().fill(isPro ? Color.cfAccent.opacity(0.12) : Color.cfSecondaryFill))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Subscription plan: \(isPro ? "Pro" : "Free")")
    }

    @ViewBuilder
    private var periodEndRow: some View {
        if let date = currentPeriodEnd {
            let isCancelling = cancelAtPeriodEnd == true
            HStack {
                Text(isCancelling ? "Cancels" : "Renews")
                    .foregroundStyle(Color.cfSecondaryLabel)
                Spacer()
                Text(date, style: .date)
                    .foregroundStyle(isCancelling ? Color.orange : Color.cfSecondaryLabel)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isCancelling
                    ? "Subscription cancels on \(date.formatted(date: .long, time: .omitted))"
                    : "Subscription renews on \(date.formatted(date: .long, time: .omitted))"
            )
        }
    }

    private var manageSubscriptionRow: some View {
        Button {
            onManageSubscription?()
        } label: {
            Label("Manage Subscription", systemImage: "creditcard")
                .foregroundStyle(Color.cfAccent)
        }
        .accessibilityLabel("Manage your subscription in the App Store")
    }

    private var freeStartsRow: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "books.vertical")
                .foregroundStyle(Color.cfSecondaryLabel)
            Text(remainingFreeStarts == 1
                 ? "1 free book start remaining"
                 : "\(remainingFreeStarts) free book starts remaining")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(remainingFreeStarts) free book \(remainingFreeStarts == 1 ? "start" : "starts") remaining"
        )
    }

    private var upgradeRow: some View {
        Button {
            onShowPaywall?()
        } label: {
            HStack {
                Label("Upgrade to ChapterFlow Pro", systemImage: "crown")
                    .foregroundStyle(Color.cfAccent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upgrade to ChapterFlow Pro")
        .accessibilityHint("Opens the subscription upgrade screen")
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Settings — Free user with starts") {
    SettingsView(
        isPro: false,
        remainingFreeStarts: 3
    )
}

#Preview("Settings — Free user, no starts") {
    SettingsView(
        isPro: false,
        remainingFreeStarts: 0
    )
}

#Preview("Settings — Pro, renewing") {
    SettingsView(
        isPro: true,
        currentPeriodEnd: Date(timeIntervalSinceNow: 28 * 24 * 3600),
        cancelAtPeriodEnd: false
    )
}

#Preview("Settings — Pro, cancelling") {
    SettingsView(
        isPro: true,
        currentPeriodEnd: Date(timeIntervalSinceNow: 10 * 24 * 3600),
        cancelAtPeriodEnd: true
    )
}

#Preview("Settings — Dark mode, Pro") {
    SettingsView(
        isPro: true,
        currentPeriodEnd: Date(timeIntervalSinceNow: 28 * 24 * 3600),
        cancelAtPeriodEnd: false
    )
    .preferredColorScheme(.dark)
}

#Preview("Settings — XXL text") {
    SettingsView(isPro: false, remainingFreeStarts: 2)
        .dynamicTypeSize(.accessibility3)
}

#endif
