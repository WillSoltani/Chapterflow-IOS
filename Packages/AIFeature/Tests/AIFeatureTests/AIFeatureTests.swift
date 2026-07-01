import Testing
@testable import AIFeature

@Suite("AIFeature")
struct AIFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(AIFeature.moduleName == "AIFeature")
    }
}
