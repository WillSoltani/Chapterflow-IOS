import Testing
@testable import SocialFeature

@Suite("SocialFeature")
struct SocialFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(SocialFeature.moduleName == "SocialFeature")
    }
}
