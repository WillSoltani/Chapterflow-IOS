import Testing
@testable import Persistence

@Suite("Persistence")
struct PersistenceTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(Persistence.moduleName == "Persistence")
    }
}
