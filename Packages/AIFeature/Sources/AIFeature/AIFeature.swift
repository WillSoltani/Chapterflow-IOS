/// AIFeature — "Ask the book", audio, concept graph, and on-device AI (P6.*).
///
/// Public surface:
/// - ``AskTheBookSheet`` — the chat sheet presented from Book Detail / Reader.
/// - ``AskTheBookModel`` — the observable view model; keep alive in presenting view state.
/// - ``AskPhase`` — the sheet's loading/error/rate-limited phase enum.
/// - ``AIRepository`` — the data contract (protocol).
/// - ``LiveAIRepository`` — production implementation (wires into `AppModel`).
/// - ``FakeAIRepository`` — test/preview fake.
/// - ``AskMessage`` — an in-memory Q&A exchange (`isOnDeviceAnswer` marks offline answers).
/// - ``BookAskResponse`` — the server response model.
/// - ``ConceptGraphView`` — the interactive concept dependency graph (P6.3).
/// - ``ConceptGraphModel`` — observable view model for the graph; keep alive in presenting view state.
/// - ``ConceptDetailSheet`` — bottom sheet for a selected concept node.
/// - ``GraphAnalyzer`` — pure graph traversal utilities (prerequisite chain, chapter analysis).
/// - ``GraphLayout`` — layered layout engine.
///
/// On-device AI (P6.5 — availability-gated; degrades silently on unsupported devices):
/// - ``OnDeviceAIAvailability`` — availability state enum.
/// - ``OnDeviceFeatureFlag`` — UserDefaults-backed feature flag.
/// - ``OnDeviceAIProviding`` — protocol for testability.
/// - ``OnDeviceAIService`` — iOS 26+ live implementation backed by `SystemLanguageModel`.
/// - ``UnavailableOnDeviceAIService`` — no-op stub for iOS < 26 / flag-off paths.
/// - ``FakeOnDeviceAIService`` — deterministic fake for tests and previews.
/// - ``makeOnDeviceAIService(flag:)`` — factory that returns the best available implementation.
/// - ``ChapterSummarySheet`` / ``ChapterSummaryModel`` — on-device chapter summary.
/// - ``HighlightExplainerSheet`` / ``HighlightExplainerModel`` — plain-language highlight explainer.
/// - ``SmartHighlightModel`` — surfaces key-sentence highlight candidates.
/// - ``SmartHighlightBanner`` — non-intrusive banner showing smart highlight suggestions.
public enum AIFeature {
    public static let moduleName = "AIFeature"
}
