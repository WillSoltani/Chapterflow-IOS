/// AIFeature — "Ask the book", audio narration player, and AI features lane (P6.*).
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
/// - ``ConceptGraphView`` — the interactive concept dependency graph (P6.3).
/// - ``ConceptGraphModel`` — observable view model for the graph; keep alive in presenting view state.
/// - ``ConceptDetailSheet`` — bottom sheet for a selected concept node.
/// - ``GraphAnalyzer`` — pure graph traversal utilities (prerequisite chain, chapter analysis).
/// - ``GraphLayout`` — layered layout engine.
/// - ``AudioPlayerModel`` — shared, long-lived model that drives `AVPlayer` (P6.2).
///   Own one instance in `AppModel` and inject it via `.environment(\.audioPlayerModel)`.
/// - ``AudioRepository`` — audio URL fetching contract.
/// - ``LiveAudioRepository`` — production implementation.
/// - ``FakeAudioRepository`` — test/preview fake.
/// - ``MiniPlayerBar`` — persistent floating mini-player mounted above the tab bar.
/// - ``NowPlayingView`` — full-screen Now Playing presented from the mini-player.
/// - ``AudioTimeline`` — reusable seek bar component.
/// - ``AudioPlaybackItem`` — value type holding context for the currently playing chapter.
public enum AIFeature {
    public static let moduleName = "AIFeature"
}
