import SwiftUI
import Models
import DesignSystem

/// The interactive concept dependency graph for a book.
///
/// Displays a layered node-link graph of all concepts, grouped by the chapter that introduces them.
/// Supports pan/zoom via gestures. Tapping a node shows its summary and prerequisite chain.
/// Respects the Reduce Motion accessibility setting (no animated layout transitions).
public struct ConceptGraphView: View {

    @State private var model: ConceptGraphModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Pan/zoom state
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @GestureState private var dragOffset: CGSize = .zero

    @State private var showDetail = false

    public init(model: ConceptGraphModel) {
        _model = State(wrappedValue: model)
    }

    // MARK: - Body

    public var body: some View {
        Group {
            switch model.phase {
            case .loading:
                loadingView
            case .loaded:
                graphContent
            case .error(let message):
                errorView(message: message)
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $showDetail) {
            if let node = model.selectedNode, let graph = model.graph {
                ConceptDetailSheet(
                    node: node,
                    graph: graph,
                    onJumpToChapter: model.onJumpToChapter
                )
                .onDisappear { model.clearSelection() }
            }
        }
        .navigationTitle("Concept Graph")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar { graphToolbar }
    }

    // MARK: - Loading / error

    private var loadingView: some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading concept graph…")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: .cfIconLarge))
                .foregroundStyle(Color.cfSecondaryLabel)
            Text("Could not load graph")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
            Text(message)
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.load() }
            }
            .buttonStyle(.bordered)
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Graph canvas

    private var graphContent: some View {
        GeometryReader { geo in
            let effectiveScale = scale * pinchScale
            let effectiveOffset = CGSize(
                width: offset.width + dragOffset.width,
                height: offset.height + dragOffset.height
            )

            graphCanvas
                .frame(width: model.canvasSize.width, height: model.canvasSize.height)
                .scaleEffect(effectiveScale, anchor: .center)
                .offset(effectiveOffset)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                .gesture(panGesture)
                .gesture(zoomGesture)
                .onTapGesture {
                    if model.selectedNodeId != nil {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            model.clearSelection()
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Concept graph with \(model.graph?.concepts.count ?? 0) concepts")
        }
        .clipped()
    }

    @ViewBuilder
    private var graphCanvas: some View {
        if let graph = model.graph {
            let positionMap = Dictionary(
                uniqueKeysWithValues: model.nodePositions.map { ($0.nodeId, $0.position) }
            )
            let highlightEdgeKeys = Set(
                model.highlightedEdges.map { "\($0.from)→\($0.to)" }
            )

            ZStack(alignment: .topLeading) {
                // Edge layer (Canvas, non-interactive)
                ConceptEdgeLayer(
                    graph: graph,
                    positions: positionMap,
                    highlightedEdges: highlightEdgeKeys,
                    highlightedNodeIds: model.highlightedNodeIds,
                    reduceMotion: reduceMotion
                )
                .frame(width: model.canvasSize.width, height: model.canvasSize.height)

                // Layer labels
                chapterLabels(for: graph, positions: positionMap)

                // Node views
                ForEach(graph.concepts) { node in
                    if let pos = positionMap[node.id] {
                        let isSelected = model.selectedNodeId == node.id
                        let isHighlighted = model.highlightedNodeIds.contains(node.id)
                        let isDimmed = !model.highlightedNodeIds.isEmpty && !isHighlighted

                        ConceptNodeView(
                            node: node,
                            isSelected: isSelected,
                            isHighlighted: isHighlighted && !isSelected,
                            isDimmed: isDimmed,
                            onTap: {
                                withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                                    model.selectNode(node.id)
                                }
                                showDetail = true
                            }
                        )
                        .position(pos)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chapterLabels(for graph: ConceptGraph, positions: [String: CGPoint]) -> some View {
        let order = GraphLayout.chapterOrder(from: graph)
        let introduces = graph.chapterIntroduces ?? [:]

        ForEach(order, id: \.self) { chapterId in
            let firstId = introduces[chapterId]?.first
            if let nodeId = firstId, let pos = positions[nodeId] {
                Text("Ch. \(chapterId)")
                    .font(.cfCaption2)
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .position(x: .cfSpacing40, y: pos.y)
            }
        }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                scale = (scale * value).clamped(to: 0.3...3.0)
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var graphToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) {
                    scale = 1.0
                    offset = .zero
                    model.clearSelection()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .accessibilityLabel("Reset view")
            }
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preview

#Preview("Concept Graph — light") {
    NavigationStack {
        ConceptGraphView(
            model: ConceptGraphModel(
                bookId: "b-atomic-habits",
                repository: FakeAIRepository()
            )
        )
    }
}

#Preview("Concept Graph — dark") {
    NavigationStack {
        ConceptGraphView(
            model: ConceptGraphModel(
                bookId: "b-atomic-habits",
                repository: FakeAIRepository()
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Concept Graph — XXL text") {
    NavigationStack {
        ConceptGraphView(
            model: ConceptGraphModel(
                bookId: "b-atomic-habits",
                repository: FakeAIRepository()
            )
        )
    }
    .dynamicTypeSize(.accessibility2)
}

#Preview("Concept Graph — error state") {
    NavigationStack {
        ConceptGraphView(
            model: ConceptGraphModel(
                bookId: "b-atomic-habits",
                repository: FakeAIRepository(graph: nil, error: .offline)
            )
        )
    }
}
