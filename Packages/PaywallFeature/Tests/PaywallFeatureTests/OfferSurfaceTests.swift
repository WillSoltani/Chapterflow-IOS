import Testing
import Foundation
import StoreKit
import CoreKit
import Networking
@testable import PaywallFeature

// StoreKit 18.4 added `SubscriptionStatus` as a typealias — disambiguate explicitly.
private typealias SubscriptionStatus = PaywallFeature.SubscriptionStatus

// MARK: - WinBackDisplayInfo tests

@Suite("WinBackDisplayInfo")
struct WinBackDisplayInfoTests {

    private func makeInfo(paymentMode: WinBackDisplayInfo.PaymentModeKind = .freeTrial) -> WinBackDisplayInfo {
        WinBackDisplayInfo(
            productID: "com.cf.annual",
            productDisplayName: "Annual Pro",
            offerDisplayPrice: "Free",
            offerPeriodText: "7 days",
            regularDisplayPrice: "$49.99",
            regularPeriodLabel: "year",
            paymentMode: paymentMode,
            offerID: "win-back-7day"
        )
    }

    @Test("public init stores all fields")
    func publicInitStoresFields() {
        let info = makeInfo()
        #expect(info.productID == "com.cf.annual")
        #expect(info.productDisplayName == "Annual Pro")
        #expect(info.offerDisplayPrice == "Free")
        #expect(info.offerPeriodText == "7 days")
        #expect(info.regularDisplayPrice == "$49.99")
        #expect(info.regularPeriodLabel == "year")
        #expect(info.paymentMode == .freeTrial)
        #expect(info.offerID == "win-back-7day")
    }

    @Test("Equatable with identical values")
    func equatable() {
        let a = makeInfo()
        let b = makeInfo()
        #expect(a == b)
    }

    @Test("Equatable with different offerID")
    func inequatable() {
        let a = makeInfo()
        let b = WinBackDisplayInfo(
            productID: "com.cf.annual", productDisplayName: "Annual Pro",
            offerDisplayPrice: "Free", offerPeriodText: "7 days",
            regularDisplayPrice: "$49.99", regularPeriodLabel: "year",
            paymentMode: .freeTrial, offerID: "other-id"
        )
        #expect(a != b)
    }

    @Test("fullDescription for freeTrial")
    func fullDescriptionFreeTrial() {
        let info = makeInfo(paymentMode: .freeTrial)
        #expect(info.fullDescription == "7 days free, then $49.99/year")
    }

    @Test("fullDescription for payUpFront includes period and regular price")
    func fullDescriptionPayUpFront() {
        let info = makeInfo(paymentMode: .payUpFront)
        #expect(info.fullDescription.contains("7 days"))
        #expect(info.fullDescription.contains("$49.99/year"))
    }

    @Test("PaymentModeKind cases are equatable")
    func paymentModeEquality() {
        #expect(WinBackDisplayInfo.PaymentModeKind.freeTrial == .freeTrial)
        #expect(WinBackDisplayInfo.PaymentModeKind.payAsYouGo != .payUpFront)
    }
}

// MARK: - Offer surface PaywallModel tests

@Suite("PaywallModel — Offer Surface")
@MainActor
struct PaywallModelOfferSurfaceTests {

    @Test("redeemOfferCode sets showOfferCodeRedemption to true")
    func redeemOfferCodeSetsFlag() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        #expect(!model.showOfferCodeRedemption)
        model.redeemOfferCode()
        #expect(model.showOfferCodeRedemption)
    }

    @Test("purchaseWinBack with no winBackDisplay sets errorMessage")
    func purchaseWinBackNoDisplay() async {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        await model.purchaseWinBack()
        #expect(model.errorMessage != nil)
        #expect(model.purchaseState == .idle)
    }

    @Test("inject sets winBackDisplay")
    func injectWinBackDisplay() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        let winBack = WinBackDisplayInfo(
            productID: "com.cf.annual",
            productDisplayName: "Annual Pro",
            offerDisplayPrice: "Free",
            offerPeriodText: "7 days",
            regularDisplayPrice: "$49.99",
            regularPeriodLabel: "year",
            paymentMode: .freeTrial,
            offerID: "wb-1"
        )
        model.inject(
            productInfos: [],
            status: .expired(productID: "com.cf.annual"),
            winBackDisplay: winBack
        )
        #expect(model.winBackDisplay == winBack)
        #expect(model.subscriptionStatus.isLapsed)
    }

    @Test("introductoryOfferText is nil on StoreProductInfo when not eligible")
    func introOfferTextNotEligible() {
        let info = StoreProductInfo(
            id: "com.cf.annual",
            displayName: "Annual",
            displayPrice: "$49.99",
            periodLabel: "year",
            isPopular: true,
            introductoryOfferText: nil
        )
        #expect(info.introductoryOfferText == nil)
    }

    @Test("introductoryOfferText is populated when eligible")
    func introOfferTextEligible() {
        let info = StoreProductInfo(
            id: "com.cf.annual",
            displayName: "Annual",
            displayPrice: "$49.99",
            periodLabel: "year",
            isPopular: true,
            introductoryOfferText: "7-day free trial"
        )
        #expect(info.introductoryOfferText == "7-day free trial")
    }

    @Test("purchaseWinBack with stub returning userCancelled resets to idle")
    func purchaseWinBackUserCancelled() async {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        let winBack = WinBackDisplayInfo(
            productID: "com.cf.annual",
            productDisplayName: "Annual Pro",
            offerDisplayPrice: "Free",
            offerPeriodText: "7 days",
            regularDisplayPrice: "$49.99",
            regularPeriodLabel: "year",
            paymentMode: .freeTrial,
            offerID: "wb-1"
        )
        model.inject(
            productInfos: [],
            status: .expired(productID: "com.cf.annual"),
            winBackDisplay: winBack
        )
        await model.purchaseWinBack()
        // StubStoreKitService default: purchaseWithWinBack returns .userCancelled → .idle
        #expect(model.purchaseState == .idle)
        #expect(model.errorMessage == nil)
    }

    @Test("eligibleIntroOfferProductIDs starts empty")
    func eligibleIntroOfferProductIDsInitiallyEmpty() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        #expect(model.eligibleIntroOfferProductIDs.isEmpty)
    }

    @Test("winBackDisplay is nil initially")
    func winBackDisplayInitiallyNil() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        #expect(model.winBackDisplay == nil)
    }
}
