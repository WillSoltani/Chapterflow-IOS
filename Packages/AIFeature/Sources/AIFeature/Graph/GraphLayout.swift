import CoreGraphics
import Models

/// Computes a layered layout for a concept graph, grouped by the chapter that introduces each node.
///
/// Nodes in the same chapter form a horizontal row (layer); layers are ordered by chapter number.
/// Nodes without an `introducedIn` chapter are collected in a final overflow layer.
public enum GraphLayout {

    // MARK: - Output

    public struct NodePosition: Sendable, Equatable {
        public let nodeId: String
        public let position: CGPoint
    }

    // MARK: - Canvas sizing

    /// Computes a canvas size that comfortably fits all layers and nodes.
    public static func canvasSize(for graph: ConceptGraph) -> CGSize {
        let order = chapterOrder(from: graph)
        let layers = buildLayers(nodes: graph.concepts, chapterOrder: order)
        let layerCount = max(layers.count, 1)
        let maxNodesInLayer = layers.map(\.count).max() ?? 1

        let width = max(600, CGFloat(maxNodesInLayer) * .nodeHorizontalSpacing + .horizontalPadding * 2)
        let height = max(400, CGFloat(layerCount) * .layerVerticalSpacing + .verticalPadding * 2)
        return CGSize(width: width, height: height)
    }

    // MARK: - Layout computation

    /// Returns `NodePosition` values for every node in the graph using a layered layout.
    public static func compute(nodes: [ConceptNode], chapterOrder: [String], canvasSize: CGSize) -> [NodePosition] {
        let layers = buildLayers(nodes: nodes, chapterOrder: chapterOrder)
        guard !layers.isEmpty else { return [] }

        let layerCount = layers.count
        var positions: [NodePosition] = []

        for (layerIndex, layer) in layers.enumerated() {
            let y: CGFloat
            if layerCount == 1 {
                y = canvasSize.height / 2
            } else {
                let usableHeight = canvasSize.height - .verticalPadding * 2
                y = .verticalPadding + CGFloat(layerIndex) * usableHeight / CGFloat(layerCount - 1)
            }

            let nodeCount = layer.count
            for (nodeIndex, node) in layer.enumerated() {
                let x: CGFloat
                if nodeCount == 1 {
                    x = canvasSize.width / 2
                } else {
                    let usableWidth = canvasSize.width - .horizontalPadding * 2
                    x = .horizontalPadding + CGFloat(nodeIndex) * usableWidth / CGFloat(nodeCount - 1)
                }
                positions.append(NodePosition(nodeId: node.id, position: CGPoint(x: x, y: y)))
            }
        }

        return positions
    }

    /// Derives the canonical chapter order from the graph (numeric sort, then alpha, then unknowns).
    public static func chapterOrder(from graph: ConceptGraph) -> [String] {
        var known = Set<String>()
        if let keys = graph.chapterIntroduces?.keys {
            known.formUnion(keys)
        }
        for node in graph.concepts {
            if let ch = node.introducedIn { known.insert(ch) }
        }
        return known.sorted { a, b in
            switch (Int(a), Int(b)) {
            case (let na?, let nb?): return na < nb
            default: return a < b
            }
        }
    }

    // MARK: - Private helpers

    private static func buildLayers(nodes: [ConceptNode], chapterOrder: [String]) -> [[ConceptNode]] {
        var byChapter: [String: [ConceptNode]] = [:]
        var unassigned: [ConceptNode] = []

        for node in nodes {
            if let chapter = node.introducedIn {
                byChapter[chapter, default: []].append(node)
            } else {
                unassigned.append(node)
            }
        }

        var layers: [[ConceptNode]] = []
        for chapter in chapterOrder {
            if let layer = byChapter[chapter], !layer.isEmpty {
                layers.append(layer)
            }
        }
        if !unassigned.isEmpty {
            layers.append(unassigned)
        }
        return layers
    }
}

// MARK: - Layout constants

private extension CGFloat {
    static let horizontalPadding: CGFloat = 80
    static let verticalPadding: CGFloat = 80
    static let nodeHorizontalSpacing: CGFloat = 160
    static let layerVerticalSpacing: CGFloat = 160
}
