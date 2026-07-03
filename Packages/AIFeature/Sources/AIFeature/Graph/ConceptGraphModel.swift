import Foundation
import Observation
import CoreKit
import Models

/// The loading phase of the concept graph screen.
public enum GraphPhase: Equatable {
    case loading
    case loaded
    case error(String)
}

/// Observable view model for the concept graph view (P6.3).
///
/// Owns all graph state: which node is selected, the prerequisite chain highlight set,
/// the computed layout positions, and the chapter filter selection.
/// Keep alive in the presenting view's `@State`.
@Observable
@MainActor
public final class ConceptGraphModel {

    // MARK: - Public state

    public private(set) var phase: GraphPhase = .loading
    public private(set) var graph: ConceptGraph?
    public private(set) var nodePositions: [GraphLayout.NodePosition] = []
    public private(set) var canvasSize: CGSize = .zero

    /// The currently selected node ID (nil = nothing selected).
    public private(set) var selectedNodeId: String?

    /// IDs of nodes emphasized due to the current selection's prerequisite chain.
    public private(set) var highlightedNodeIds: Set<String> = []

    /// Edges to emphasize when a node is selected.
    public private(set) var highlightedEdges: [ConceptEdge] = []

    // MARK: - Configuration

    public let bookId: String

    /// Called when the user taps "Go to Chapter" in the detail sheet.
    public var onJumpToChapter: ((String) -> Void)?

    // MARK: - Private

    private let repository: any AIRepository

    // MARK: - Init

    public init(bookId: String, repository: any AIRepository) {
        self.bookId = bookId
        self.repository = repository
    }

    // MARK: - Load

    public func load() async {
        phase = .loading
        do {
            let loaded = try await repository.conceptGraph(bookId: bookId)
            graph = loaded
            recomputeLayout(for: loaded)
            phase = .loaded
        } catch let appError as AppError {
            phase = .error(appError.errorDescription ?? "Failed to load concept graph.")
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Selection

    /// Selects a node and computes its prerequisite chain highlight.
    public func selectNode(_ id: String) {
        if selectedNodeId == id {
            clearSelection()
            return
        }
        selectedNodeId = id
        guard let graph else { return }
        let chain = GraphAnalyzer.prerequisiteChain(for: id, in: graph)
        highlightedNodeIds = chain
        highlightedEdges = GraphAnalyzer.edges(connecting: chain, in: graph)
    }

    /// Clears the current selection and highlight.
    public func clearSelection() {
        selectedNodeId = nil
        highlightedNodeIds = []
        highlightedEdges = []
    }

    /// Returns the `ConceptNode` for the currently selected node ID, or `nil`.
    public var selectedNode: ConceptNode? {
        guard let id = selectedNodeId else { return nil }
        return graph?.concepts.first { $0.id == id }
    }

    // MARK: - Navigation

    /// Fires the `onJumpToChapter` callback for the node's introducing chapter.
    public func jumpToChapter(for node: ConceptNode) {
        guard let chapterId = node.introducedIn else { return }
        onJumpToChapter?(chapterId)
    }

    // MARK: - Chapter filtering

    /// Returns the set of concept IDs introduced by the given chapter.
    public func conceptsIntroduced(by chapterId: String) -> Set<String> {
        guard let graph else { return [] }
        return GraphAnalyzer.conceptsIntroduced(by: chapterId, in: graph)
    }

    /// Returns the set of concept IDs required by the given chapter.
    public func conceptsRequired(by chapterId: String) -> Set<String> {
        guard let graph else { return [] }
        return GraphAnalyzer.conceptsRequired(by: chapterId, in: graph)
    }

    // MARK: - Private

    private func recomputeLayout(for graph: ConceptGraph) {
        let size = GraphLayout.canvasSize(for: graph)
        canvasSize = size
        let order = GraphLayout.chapterOrder(from: graph)
        nodePositions = GraphLayout.compute(nodes: graph.concepts, chapterOrder: order, canvasSize: size)
    }
}
