import SwiftUI
import Models
import DesignSystem

/// A `Canvas`-based view that draws directed edges between concept nodes.
///
/// Renders bezier curves for all edges, with emphasis for highlighted edges
/// (those in the selected node's prerequisite chain).
struct ConceptEdgeLayer: View {

    let graph: ConceptGraph
    let positions: [String: CGPoint]
    let highlightedEdges: Set<String>  // "from→to" keys
    let highlightedNodeIds: Set<String>
    let reduceMotion: Bool

    var body: some View {
        Canvas { context, size in
            drawEdges(in: context, size: size)
        }
        .allowsHitTesting(false)
    }

    private func drawEdges(in context: GraphicsContext, size: CGSize) {
        for edge in graph.edges {
            guard let fromPt = positions[edge.from],
                  let toPt = positions[edge.to] else { continue }

            let key = "\(edge.from)→\(edge.to)"
            let isHighlighted = highlightedEdges.contains(key)
            let isInChain = !highlightedNodeIds.isEmpty
            let isDimmed = isInChain && !isHighlighted

            // Build the bezier path
            let path = curvePath(from: fromPt, to: toPt)

            // Draw
            if isDimmed {
                context.stroke(
                    path,
                    with: .color(.cfSeparator),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            } else {
                let color: Color = isHighlighted ? .cfAccent : .cfSecondaryLabel
                let lineWidth: CGFloat = isHighlighted ? 2 : 1
                context.stroke(
                    path,
                    with: .color(color.opacity(isHighlighted ? 1 : 0.5)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                // Arrow head for prerequisite edges
                if case .prerequisite = edge.edgeType {
                    drawArrow(in: context, from: fromPt, to: toPt, color: color, highlighted: isHighlighted)
                }
            }
        }
    }

    private func curvePath(from start: CGPoint, to end: CGPoint) -> Path {
        Path { path in
            path.move(to: start)
            let midY = (start.y + end.y) / 2
            let ctrl1 = CGPoint(x: start.x, y: midY)
            let ctrl2 = CGPoint(x: end.x, y: midY)
            path.addCurve(to: end, control1: ctrl1, control2: ctrl2)
        }
    }

    private func drawArrow(
        in context: GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        highlighted: Bool
    ) {
        // Offset the arrowhead to the edge of the destination node circle
        let nodeRadius: CGFloat = .nodeRadius + .cfSpacing4
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 1)
        let nx = dx / length
        let ny = dy / length

        let tip = CGPoint(x: end.x - nx * nodeRadius, y: end.y - ny * nodeRadius)

        let arrowSize: CGFloat = 7
        let angle = atan2(ny, nx)
        let leftAngle = angle + .pi * 0.75
        let rightAngle = angle - .pi * 0.75

        let arrowPath = Path { path in
            path.move(to: tip)
            path.addLine(to: CGPoint(
                x: tip.x + arrowSize * cos(leftAngle),
                y: tip.y + arrowSize * sin(leftAngle)
            ))
            path.move(to: tip)
            path.addLine(to: CGPoint(
                x: tip.x + arrowSize * cos(rightAngle),
                y: tip.y + arrowSize * sin(rightAngle)
            ))
        }

        context.stroke(
            arrowPath,
            with: .color(color.opacity(highlighted ? 1 : 0.5)),
            style: StrokeStyle(lineWidth: highlighted ? 2 : 1, lineCap: .round)
        )
    }
}

extension CGFloat {
    static let nodeRadius: CGFloat = 28
}
