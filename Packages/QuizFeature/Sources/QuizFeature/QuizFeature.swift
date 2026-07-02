/// QuizFeature provides the Quiz experience for ChapterFlow.
///
/// Entry points:
/// - ``QuizView``: present a quiz for a given book chapter.
/// - ``LiveQuizRepository``: production data source backed by the REST API.
/// - ``FakeQuizRepository``: in-memory fake for tests and previews.
///
/// Architecture: ``QuizModel`` (@Observable, @MainActor) drives ``QuizView``.
/// The server is the **sole grader** — answers are never evaluated client-side.
public enum QuizFeature {
    public static let moduleName = "QuizFeature"
}
