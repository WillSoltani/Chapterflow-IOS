import Testing
import Foundation
@testable import AIFeature
import Models
import CoreKit

// MARK: - GraphAnalyzer tests

@Suite("GraphAnalyzer — prerequisite chains")
struct GraphAnalyzerChainTests {

    // Build a small graph: A → B → C (A is prerequisite of B, B of C)
    private static func makeLinearGraph() -> ConceptGraph {
        ConceptGraph(
            concepts: [
                ConceptNode(id: "a", label: "A", introducedIn: "1"),
                ConceptNode(id: "b", label: "B", introducedIn: "2"),
                ConceptNode(id: "c", label: "C", introducedIn: "3")
            ],
            edges: [
                ConceptEdge(from: "a", to: "b", edgeType: .prerequisite),
                ConceptEdge(from: "b", to: "c", edgeType: .prerequisite)
            ]
        )
    }

    @Test("chain of middle node includes ancestor and descendant")
    func middleNodeChain() {
        let graph = Self.makeLinearGraph()
        let chain = GraphAnalyzer.prerequisiteChain(for: "b", in: graph)
        #expect(chain == Set(["a", "b", "c"]))
    }

    @Test("chain of leaf node includes all ancestors")
    func leafNodeChain() {
        let graph = Self.makeLinearGraph()
        let chain = GraphAnalyzer.prerequisiteChain(for: "c", in: graph)
        #expect(chain == Set(["a", "b", "c"]))
    }

    @Test("chain of root node includes all descendants")
    func rootNodeChain() {
        let graph = Self.makeLinearGraph()
        let chain = GraphAnalyzer.prerequisiteChain(for: "a", in: graph)
        #expect(chain == Set(["a", "b", "c"]))
    }

    @Test("chain of isolated node is just itself")
    func isolatedNodeChain() {
        let graph = ConceptGraph(
            concepts: [ConceptNode(id: "x", label: "X")],
            edges: []
        )
        let chain = GraphAnalyzer.prerequisiteChain(for: "x", in: graph)
        #expect(chain == Set(["x"]))
    }

    @Test("unknown edge type edges are excluded from chain traversal")
    func unknownEdgesIgnored() {
        let graph = ConceptGraph(
            concepts: [
                ConceptNode(id: "a", label: "A"),
                ConceptNode(id: "b", label: "B")
            ],
            edges: [
                ConceptEdge(from: "a", to: "b", edgeType: .unknown("associates_with"))
            ]
        )
        let chain = GraphAnalyzer.prerequisiteChain(for: "a", in: graph)
        #expect(chain == Set(["a"]))
    }

    @Test("diamond-shaped prereq graph resolves correctly")
    func diamondGraph() {
        // A → B → D
        // A → C → D
        let graph = ConceptGraph(
            concepts: [
                ConceptNode(id: "a", label: "A"),
                ConceptNode(id: "b", label: "B"),
                ConceptNode(id: "c", label: "C"),
                ConceptNode(id: "d", label: "D")
            ],
            edges: [
                ConceptEdge(from: "a", to: "b", edgeType: .prerequisite),
                ConceptEdge(from: "a", to: "c", edgeType: .prerequisite),
                ConceptEdge(from: "b", to: "d", edgeType: .prerequisite),
                ConceptEdge(from: "c", to: "d", edgeType: .prerequisite)
            ]
        )
        let chainForB = GraphAnalyzer.prerequisiteChain(for: "b", in: graph)
        #expect(chainForB.contains("a"))
        #expect(chainForB.contains("b"))
        #expect(chainForB.contains("d"))
    }

    @Test("highlighted edges connects only nodes in the chain set")
    func highlightedEdgesFiltered() {
        let graph = Self.makeLinearGraph()
        let chain = Set(["a", "b"])
        let edges = GraphAnalyzer.edges(connecting: chain, in: graph)
        #expect(edges.count == 1)
        #expect(edges[0].from == "a")
        #expect(edges[0].to == "b")
    }
}

// MARK: - GraphAnalyzer chapter analysis tests

@Suite("GraphAnalyzer — chapter analysis")
struct GraphAnalyzerChapterTests {

    private static func makeChapterGraph() -> ConceptGraph {
        ConceptGraph(
            concepts: [
                ConceptNode(id: "c1", label: "Concept 1", introducedIn: "ch-1"),
                ConceptNode(id: "c2", label: "Concept 2", introducedIn: "ch-2")
            ],
            edges: [],
            chapterIntroduces: ["ch-1": ["c1"], "ch-2": ["c2"]],
            chapterRequires: ["ch-2": ["c1"]]
        )
    }

    @Test("conceptsIntroduced returns correct IDs for known chapter")
    func introducedByChapter() {
        let graph = Self.makeChapterGraph()
        let ids = GraphAnalyzer.conceptsIntroduced(by: "ch-1", in: graph)
        #expect(ids == Set(["c1"]))
    }

    @Test("conceptsRequired returns correct IDs for known chapter")
    func requiredByChapter() {
        let graph = Self.makeChapterGraph()
        let ids = GraphAnalyzer.conceptsRequired(by: "ch-2", in: graph)
        #expect(ids == Set(["c1"]))
    }

    @Test("conceptsIntroduced returns empty for unknown chapter")
    func unknownChapterIntroduced() {
        let graph = Self.makeChapterGraph()
        let ids = GraphAnalyzer.conceptsIntroduced(by: "ch-99", in: graph)
        #expect(ids.isEmpty)
    }

    @Test("conceptsRequired returns empty for unknown chapter")
    func unknownChapterRequired() {
        let graph = Self.makeChapterGraph()
        let ids = GraphAnalyzer.conceptsRequired(by: "ch-99", in: graph)
        #expect(ids.isEmpty)
    }

    @Test("isAcyclic returns true for DAG")
    func acyclicGraph() {
        let graph = ConceptGraph(
            concepts: [
                ConceptNode(id: "a", label: "A"),
                ConceptNode(id: "b", label: "B"),
                ConceptNode(id: "c", label: "C")
            ],
            edges: [
                ConceptEdge(from: "a", to: "b", edgeType: .prerequisite),
                ConceptEdge(from: "b", to: "c", edgeType: .prerequisite)
            ]
        )
        #expect(GraphAnalyzer.isAcyclic(graph))
    }

    @Test("isAcyclic returns false for cyclic graph")
    func cyclicGraph() {
        let graph = ConceptGraph(
            concepts: [
                ConceptNode(id: "a", label: "A"),
                ConceptNode(id: "b", label: "B")
            ],
            edges: [
                ConceptEdge(from: "a", to: "b", edgeType: .prerequisite),
                ConceptEdge(from: "b", to: "a", edgeType: .prerequisite)
            ]
        )
        #expect(!GraphAnalyzer.isAcyclic(graph))
    }

    @Test("sample concept graph is a valid DAG")
    func sampleGraphIsAcyclic() {
        #expect(GraphAnalyzer.isAcyclic(FakeAIRepository.sampleConceptGraph))
    }
}

// MARK: - GraphLayout tests

@Suite("GraphLayout")
struct GraphLayoutTests {

    @Test("single layer positions all nodes horizontally centered")
    func singleLayer() {
        let nodes = [
            ConceptNode(id: "a", label: "A", introducedIn: "1"),
            ConceptNode(id: "b", label: "B", introducedIn: "1"),
            ConceptNode(id: "c", label: "C", introducedIn: "1")
        ]
        let size = CGSize(width: 600, height: 400)
        let positions = GraphLayout.compute(nodes: nodes, chapterOrder: ["1"], canvasSize: size)
        #expect(positions.count == 3)
        // All y values should be the same (single layer at canvas center)
        let ys = Set(positions.map { $0.position.y })
        #expect(ys.count == 1)
    }

    @Test("multiple layers produce increasing y values")
    func multipleLayers() throws {
        let nodes = [
            ConceptNode(id: "a", label: "A", introducedIn: "1"),
            ConceptNode(id: "b", label: "B", introducedIn: "2"),
            ConceptNode(id: "c", label: "C", introducedIn: "3")
        ]
        let size = CGSize(width: 600, height: 400)
        let positions = GraphLayout.compute(nodes: nodes, chapterOrder: ["1", "2", "3"], canvasSize: size)
        #expect(positions.count == 3)

        let byId = Dictionary(uniqueKeysWithValues: positions.map { ($0.nodeId, $0.position.y) })
        let yA = try #require(byId["a"])
        let yB = try #require(byId["b"])
        let yC = try #require(byId["c"])
        #expect(yA < yB)
        #expect(yB < yC)
    }

    @Test("nodes without chapter are placed in final overflow layer")
    func overflowLayer() throws {
        let nodes = [
            ConceptNode(id: "a", label: "A", introducedIn: "1"),
            ConceptNode(id: "unassigned", label: "U")
        ]
        let size = CGSize(width: 600, height: 400)
        let positions = GraphLayout.compute(nodes: nodes, chapterOrder: ["1"], canvasSize: size)
        #expect(positions.count == 2)

        let byId = Dictionary(uniqueKeysWithValues: positions.map { ($0.nodeId, $0.position.y) })
        let yA = try #require(byId["a"])
        let yU = try #require(byId["unassigned"])
        // Unassigned should be below the first layer
        #expect(yA < yU)
    }

    @Test("all positions are within canvas bounds")
    func positionsInBounds() {
        let size = CGSize(width: 800, height: 600)
        let graph = FakeAIRepository.sampleConceptGraph
        let order = GraphLayout.chapterOrder(from: graph)
        let positions = GraphLayout.compute(nodes: graph.concepts, chapterOrder: order, canvasSize: size)
        for pos in positions {
            #expect(pos.position.x >= 0 && pos.position.x <= size.width)
            #expect(pos.position.y >= 0 && pos.position.y <= size.height)
        }
    }

    @Test("chapterOrder sorts numerically")
    func chapterOrderNumericSort() {
        let graph = ConceptGraph(
            concepts: [
                ConceptNode(id: "a", label: "A", introducedIn: "10"),
                ConceptNode(id: "b", label: "B", introducedIn: "2")
            ],
            edges: [],
            chapterIntroduces: ["10": ["a"], "2": ["b"]]
        )
        let order = GraphLayout.chapterOrder(from: graph)
        #expect(order == ["2", "10"])
    }

    @Test("canvasSize grows with more layers and nodes")
    func canvasSizeGrows() {
        let smallGraph = ConceptGraph(
            concepts: [ConceptNode(id: "a", label: "A")],
            edges: []
        )
        let largeGraph = FakeAIRepository.sampleConceptGraph
        let small = GraphLayout.canvasSize(for: smallGraph)
        let large = GraphLayout.canvasSize(for: largeGraph)
        #expect(large.width >= small.width || large.height >= small.height)
    }
}

// MARK: - ConceptGraphModel tests

@Suite("ConceptGraphModel")
@MainActor
struct ConceptGraphModelTests {

    @Test("load transitions from loading to loaded on success")
    func loadSuccess() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.graph != nil)
    }

    @Test("load transitions to error on repository failure")
    func loadError() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository(graph: nil, error: .offline)
        )
        await model.load()
        if case .error = model.phase {
            // expected
        } else {
            Issue.record("Expected .error phase, got \(model.phase)")
        }
    }

    @Test("selectNode sets selectedNodeId and highlight")
    func selectNode() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()
        model.selectNode("habit-loop")
        #expect(model.selectedNodeId == "habit-loop")
        #expect(!model.highlightedNodeIds.isEmpty)
        #expect(model.highlightedNodeIds.contains("habit-loop"))
    }

    @Test("selectNode same node twice clears selection")
    func selectSameNodeClears() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()
        model.selectNode("habit-loop")
        model.selectNode("habit-loop")
        #expect(model.selectedNodeId == nil)
        #expect(model.highlightedNodeIds.isEmpty)
    }

    @Test("clearSelection resets all highlight state")
    func clearSelection() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()
        model.selectNode("habit-loop")
        model.clearSelection()
        #expect(model.selectedNodeId == nil)
        #expect(model.highlightedNodeIds.isEmpty)
        #expect(model.highlightedEdges.isEmpty)
    }

    @Test("selectedNode returns the ConceptNode for selectedNodeId")
    func selectedNodeProperty() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()
        model.selectNode("habit-loop")
        #expect(model.selectedNode?.id == "habit-loop")
        #expect(model.selectedNode?.label == "Habit Loop")
    }

    @Test("selectedNode returns nil when no selection")
    func selectedNodeNil() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()
        #expect(model.selectedNode == nil)
    }

    @Test("nodePositions are populated after load")
    func nodePositionsPopulated() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()
        #expect(!model.nodePositions.isEmpty)
        #expect(model.nodePositions.count == FakeAIRepository.sampleConceptGraph.concepts.count)
    }

    @Test("jumpToChapter fires callback with correct chapter ID")
    func jumpToChapterCallback() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()

        var receivedChapterId: String?
        model.onJumpToChapter = { receivedChapterId = $0 }

        if let node = model.graph?.concepts.first(where: { $0.introducedIn != nil }) {
            model.jumpToChapter(for: node)
            #expect(receivedChapterId == node.introducedIn)
        } else {
            Issue.record("No node with introducedIn found in sample graph")
        }
    }

    @Test("conceptsIntroduced delegates to GraphAnalyzer correctly")
    func conceptsIntroduced() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()
        let ids = model.conceptsIntroduced(by: "1")
        // Chapter 1 introduces habit-loop, cue, craving, reward, compound-growth
        #expect(ids.count == 5)
        #expect(ids.contains("habit-loop"))
    }

    @Test("conceptsRequired delegates to GraphAnalyzer correctly")
    func conceptsRequired() async {
        let model = ConceptGraphModel(
            bookId: "b-test",
            repository: FakeAIRepository()
        )
        await model.load()
        let ids = model.conceptsRequired(by: "2")
        #expect(ids.contains("habit-loop"))
    }
}
