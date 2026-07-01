import Testing
@testable import PaywallFeature

@Suite("PaywallFeature")
struct PaywallFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(PaywallFeature.moduleName == "PaywallFeature")
    }
}
