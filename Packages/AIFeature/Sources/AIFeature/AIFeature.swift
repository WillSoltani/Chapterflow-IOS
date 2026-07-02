/// AIFeature — "Ask the book" and the AI features lane (P6.*).
///
/// Public surface:
/// - ``AskTheBookSheet`` — the chat sheet presented from Book Detail / Reader.
/// - ``AskTheBookModel`` — the observable view model; keep alive in presenting view state.
/// - ``AskPhase`` — the sheet's loading/error/rate-limited phase enum.
/// - ``AIRepository`` — the data contract (protocol).
/// - ``LiveAIRepository`` — production implementation (wires into `AppModel`).
/// - ``FakeAIRepository`` — test/preview fake.
/// - ``AskMessage`` — an in-memory Q&A exchange.
/// - ``BookAskResponse`` — the server response model.
public enum AIFeature {
    public static let moduleName = "AIFeature"
}
