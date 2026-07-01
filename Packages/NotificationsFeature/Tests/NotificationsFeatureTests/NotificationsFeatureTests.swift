import Testing
@testable import NotificationsFeature

@Suite("NotificationsFeature")
struct NotificationsFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(NotificationsFeature.moduleName == "NotificationsFeature")
    }
}
