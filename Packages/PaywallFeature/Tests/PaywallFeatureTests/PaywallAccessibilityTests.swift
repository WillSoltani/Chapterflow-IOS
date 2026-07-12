import Testing
@testable import PaywallFeature

@Suite("Paywall accessibility disclosures")
@MainActor
struct PaywallAccessibilityTests {
    @Test("introductory plan announces trial, renewal price, and savings")
    func introductoryPlanDisclosure() {
        let row = ProductOptionRow(
            info: StoreProductInfo(
                id: "com.example.pro.annual",
                displayName: "Annual",
                displayPrice: "$49.99",
                periodLabel: "year",
                isPopular: true,
                introductoryOfferText: "7-day free trial"
            ),
            isSelected: true,
            savingsPercent: 30,
            onTap: {}
        )

        #expect(row.accessibilityDescription.contains("7-day free trial"))
        #expect(row.accessibilityDescription.contains("then $49.99 per year"))
        #expect(row.accessibilityDescription.contains("renews automatically"))
        #expect(row.accessibilityDescription.contains("save 30 percent"))
    }

    @Test("regular plan still announces automatic renewal")
    func regularPlanDisclosure() {
        let row = ProductOptionRow(
            info: StoreProductInfo(
                id: "com.example.pro.monthly",
                displayName: "Monthly",
                displayPrice: "$5.99",
                periodLabel: "month",
                isPopular: false
            ),
            isSelected: false,
            savingsPercent: nil,
            onTap: {}
        )

        #expect(row.accessibilityDescription.contains("$5.99 per month"))
        #expect(row.accessibilityDescription.contains("renews automatically"))
        #expect(!row.accessibilityDescription.contains("trial"))
    }
}
