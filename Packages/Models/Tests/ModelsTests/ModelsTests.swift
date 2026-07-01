import Testing
@testable import Models

@Suite("Models")
struct ModelsTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(Models.moduleName == "Models")
    }
}
