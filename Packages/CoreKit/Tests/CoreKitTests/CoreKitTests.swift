import Testing
@testable import CoreKit

@Suite("CoreKit")
struct CoreKitTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(CoreKit.moduleName == "CoreKit")
    }
}
