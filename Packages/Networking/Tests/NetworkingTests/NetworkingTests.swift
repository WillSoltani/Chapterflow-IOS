import Testing
@testable import Networking

@Suite("Networking")
struct NetworkingTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(Networking.moduleName == "Networking")
    }
}
