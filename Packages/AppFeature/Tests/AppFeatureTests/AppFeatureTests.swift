import Testing
@testable import AppFeature

@Suite("AppFeature")
struct AppFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(AppFeature.moduleName == "AppFeature")
    }
}
