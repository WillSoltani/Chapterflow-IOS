import Testing
@testable import AuthKit

@Suite("AuthKit")
struct AuthKitTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(AuthKit.moduleName == "AuthKit")
    }
}
