import Testing
@testable import AuthKit
import Persistence
import Foundation

@Suite("AuthKit")
struct AuthKitTests {
    @Test("module compiles")
    func moduleExists() {
        _ = AuthKit.self
    }
}
