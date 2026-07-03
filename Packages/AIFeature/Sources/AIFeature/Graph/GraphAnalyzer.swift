import Models

/// Pure graph traversal utilities for the concept dependency graph.
///
/// All methods are stateless and `Sendable`-safe; they take values and return values.
public enum GraphAnalyzer {

    // MARK: - Prerequisite chain

    /// Returns the set of node IDs in the prerequisite chain of a given node.
    ///
    /// Includes the selected node itself, all of its ancestors (nodes it depends on, recursively),
    /// and all of its descendants (nodes that depend on it, recursively), traversing only
    /// `.prerequisite` edges.
    public static func prerequisiteChain(for nodeId: String, in graph: ConceptGraph) -> Set<String> {
        var result = Set<String>([nodeId])

        // Ancestors: nodes that nodeId transitively requires (traverse edges backward: edge.to == current → add edge.from)
        var queue = [nodeId]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for edge in graph.edges {
                guard case .prerequisite = edge.edgeType else { continue }
                if edge.to == current, !result.contains(edge.from) {
                    result.insert(edge.from)
                    queue.append(edge.from)
                }
            }
        }

        // Descendants: nodes that transitively require nodeId (traverse edges forward: edge.from == current → add edge.to)
        queue = [nodeId]
        var visited = Set<String>([nodeId])
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for edge in graph.edges {
                guard case .prerequisite = edge.edgeType else { continue }
                if edge.from == current, !visited.contains(edge.to) {
                    visited.insert(edge.to)
                    result.insert(edge.to)
                    queue.append(edge.to)
                }
            }
        }

        return result
    }

    /// Returns the prerequisite edges that connect nodes within a given set of node IDs.
    public static func edges(
        connecting nodeIds: Set<String>,
        in graph: ConceptGraph
    ) -> [ConceptEdge] {
        graph.edges.filter { edge in
            guard case .prerequisite = edge.edgeType else { return false }
            return nodeIds.contains(edge.from) && nodeIds.contains(edge.to)
        }
    }

    // MARK: - Chapter analysis

    /// Returns the set of concept IDs introduced by the given chapter.
    public static func conceptsIntroduced(by chapterId: String, in graph: ConceptGraph) -> Set<String> {
        Set(graph.chapterIntroduces?[chapterId] ?? [])
    }

    /// Returns the set of concept IDs required by the given chapter.
    public static func conceptsRequired(by chapterId: String, in graph: ConceptGraph) -> Set<String> {
        Set(graph.chapterRequires?[chapterId] ?? [])
    }

    /// Returns `true` if every prerequisite edge from the given graph is acyclic (no cycles detected).
    /// Used in tests to validate sample data.
    public static func isAcyclic(_ graph: ConceptGraph) -> Bool {
        var visited = Set<String>()
        var stack = Set<String>()

        func dfs(_ nodeId: String) -> Bool {
            if stack.contains(nodeId) { return false } // cycle
            if visited.contains(nodeId) { return true }
            visited.insert(nodeId)
            stack.insert(nodeId)
            for edge in graph.edges {
                guard case .prerequisite = edge.edgeType, edge.from == nodeId else { continue }
                if !dfs(edge.to) { return false }
            }
            stack.remove(nodeId)
            return true
        }

        return graph.concepts.allSatisfy { dfs($0.id) }
    }
}
