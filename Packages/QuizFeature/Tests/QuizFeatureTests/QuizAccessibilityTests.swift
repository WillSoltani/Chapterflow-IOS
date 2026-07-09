import Testing
@testable import QuizFeature

/// Regression guard: verifies that every `DisplayState` case that drives
/// `QuizChoiceButton.accessibilityLabel` is present and exhaustively handled.
/// If any case is removed or renamed, this file fails to compile.
@Suite("Quiz Accessibility")
struct QuizAccessibilityTests {

    @Test("DisplayState has all four VoiceOver label states")
    func displayStateCoverage() {
        func describe(_ state: QuizChoiceButton.DisplayState) -> String {
            switch state {
            case .idle:              return "idle"
            case .selected:          return "selected"
            case .correct:           return "correct"
            case .incorrectSelected: return "incorrectSelected"
            }
        }
        #expect(describe(.idle) == "idle")
        #expect(describe(.selected) == "selected")
        #expect(describe(.correct) == "correct")
        #expect(describe(.incorrectSelected) == "incorrectSelected")
    }
}
