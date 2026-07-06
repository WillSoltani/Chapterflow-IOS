import Foundation

/// Errors specific to quiz submission that are distinct from general ``AppError`` cases.
public enum QuizSubmissionError: Error, Sendable {
    /// The quiz was submitted while offline.
    ///
    /// The answers have been saved to the outbox (``PendingMutation/MutationKind/quizSubmit``)
    /// and will be graded by the server when connectivity is restored.
    /// The UI should show a "pending grading" state rather than an error.
    case pendingGrading
}
