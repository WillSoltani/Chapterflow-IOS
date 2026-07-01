import Testing
@testable import SettingsFeature

@Suite("SettingsFeature")
struct SettingsFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(SettingsFeature.moduleName == "SettingsFeature")
    }
}
