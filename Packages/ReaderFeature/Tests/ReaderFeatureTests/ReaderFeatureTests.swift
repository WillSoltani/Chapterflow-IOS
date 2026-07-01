import Testing
@testable import ReaderFeature

@Suite("ReaderFeature")
struct ReaderFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(ReaderFeature.moduleName == "ReaderFeature")
    }
}
