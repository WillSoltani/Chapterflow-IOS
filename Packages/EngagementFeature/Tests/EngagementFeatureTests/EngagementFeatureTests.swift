import Testing
@testable import EngagementFeature

@Suite("EngagementFeature")
struct EngagementFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(EngagementFeature.moduleName == "EngagementFeature")
    }
}
