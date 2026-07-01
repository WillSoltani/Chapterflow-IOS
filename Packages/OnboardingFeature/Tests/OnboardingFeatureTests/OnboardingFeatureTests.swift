import Testing
@testable import OnboardingFeature

@Suite("OnboardingFeature")
struct OnboardingFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(OnboardingFeature.moduleName == "OnboardingFeature")
    }
}
