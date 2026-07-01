import Testing
@testable import QuizFeature

@Suite("QuizFeature")
struct QuizFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(QuizFeature.moduleName == "QuizFeature")
    }
}
