import Testing
@testable import DesignSystem

@Suite("DesignSystem")
struct DesignSystemTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(DesignSystem.moduleName == "DesignSystem")
    }
}
