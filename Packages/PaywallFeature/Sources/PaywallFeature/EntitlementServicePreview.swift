import SwiftUI
import StoreKit
import Models
import Networking
import Persistence

// MARK: - Preview StoreKit stub

private actor PreviewStoreKitService: StoreKitServicing {
    nonisolated let entitlementChanges: AsyncStream<Void> = AsyncStream { _ in }
    private let isProStatus: Bool

    init(isPro: Bool = false) { isProStatus = isPro }

    func loadProducts() async throws -> [Product] { [] }
    func purchase(_ product: Product) async throws -> PurchaseResult { .userCancelled }
    func restorePurchases() async throws {}
    func verifyCurrentEntitlements() async throws {}
    func currentSubscriptionStatus() async throws -> SubscriptionStatus {
        isProStatus ? .subscribed(productID: "com.cf.annual", expirationDate: nil) : .notSubscribed
    }
    func currentTransactionID() async -> UInt64? { nil }
}

// MARK: - Factory

@MainActor
private func previewService(
    plan: Entitlement.Plan,
    proStatus: String? = nil,
    remainingFreeStarts: Int = 0,
    freeBookSlots: Int = 0,
    unlockedBookIds: [String] = [],
    storeKitIsPro: Bool = false
) -> EntitlementService {
    let entitlement = Entitlement(
        plan: plan,
        proStatus: proStatus,
        proSource: plan == .pro ? "apple" : nil,
        freeBookSlots: freeBookSlots,
        unlockedBookIds: unlockedBookIds,
        unlockedBooksCount: unlockedBookIds.count,
        remainingFreeStarts: remainingFreeStarts,
        currentPeriodEnd: nil,
        cancelAtPeriodEnd: nil,
        licenseKey: nil,
        licenseExpiresAt: nil
    )
    let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
    let store = KeyValueStore(defaults: defaults)
    // Write to cache before init — service reads it synchronously in init.
    try? store.set(entitlement, forKey: "com.chapterflow.entitlement.v1")
    return EntitlementService(
        storeKitService: PreviewStoreKitService(isPro: storeKitIsPro),
        apiClient: MockAPIClient(),
        store: store
    )
}

// MARK: - Diagnostic view

private struct EntitlementStatusView: View {
    let service: EntitlementService
    let bookId: String

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("isPro", value: service.isPro ? "✓ true" : "false")
                LabeledContent("canStartNewBook", value: service.canStartNewBook ? "✓ true" : "false")
            }
            Section("Book: \(bookId)") {
                LabeledContent("isBookUnlocked", value: service.isBookUnlocked(bookId) ? "✓ true" : "false")
                LabeledContent("lockReason", value: label(service.lockReason(for: bookId)))
                LabeledContent("lockReason (quiz)", value: label(service.lockReason(for: bookId, isLockedByQuiz: true)))
            }
        }
        .navigationTitle("EntitlementService")
    }

    private func label(_ reason: LockReason?) -> String {
        switch reason {
        case .none:
            return "nil — accessible"
        case .needsPro:
            return "needsPro"
        case .needsFreeSlotOrPro:
            return "needsFreeSlotOrPro"
        case .lockedBehindQuiz:
            return "lockedBehindQuiz"
        }
    }
}

// MARK: - Previews

#Preview("Free — 3 free starts") {
    NavigationStack {
        EntitlementStatusView(
            service: previewService(plan: .free, remainingFreeStarts: 3, freeBookSlots: 5),
            bookId: "book-locked"
        )
    }
}

#Preview("Free — no starts, had slots") {
    NavigationStack {
        EntitlementStatusView(
            service: previewService(plan: .free, remainingFreeStarts: 0, freeBookSlots: 5),
            bookId: "book-locked"
        )
    }
}

#Preview("Free — no starts, no slots") {
    NavigationStack {
        EntitlementStatusView(
            service: previewService(plan: .free, remainingFreeStarts: 0, freeBookSlots: 0),
            bookId: "book-locked"
        )
    }
}

#Preview("Pro — backend active") {
    NavigationStack {
        EntitlementStatusView(
            service: previewService(plan: .pro, proStatus: "active"),
            bookId: "any-book"
        )
    }
}

// StoreKit optimism: backend is still free; after refresh StoreKit flips isPro=true.
#Preview("StoreKit optimism — SK subscribed, backend free") {
    @Previewable @State var service = previewService(plan: .free, storeKitIsPro: true)
    NavigationStack {
        EntitlementStatusView(service: service, bookId: "book-x")
            .task { await service.refresh() }
    }
}

#Preview("Pro — dark mode") {
    NavigationStack {
        EntitlementStatusView(
            service: previewService(plan: .pro, proStatus: "active"),
            bookId: "any-book"
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Free no slots — XXL text") {
    NavigationStack {
        EntitlementStatusView(
            service: previewService(plan: .free, remainingFreeStarts: 0, freeBookSlots: 0),
            bookId: "locked"
        )
    }
    .dynamicTypeSize(.accessibility3)
}
