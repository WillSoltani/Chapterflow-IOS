import Testing
@testable import LibraryFeature

@Suite("LibraryFeature")
struct LibraryFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(LibraryFeature.moduleName == "LibraryFeature")
    }
}
