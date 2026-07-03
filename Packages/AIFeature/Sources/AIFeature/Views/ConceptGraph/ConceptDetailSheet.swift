import SwiftUI
import Models
import DesignSystem

/// A bottom sheet presenting the summary of a selected concept node.
///
/// Shows the concept's label, the chapter that introduces it, a short summary,
/// and an optional "Go to Chapter" action.
public struct ConceptDetailSheet: View {

    let node: ConceptNode
    let graph: ConceptGraph
    let onJumpToChapter: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    public init(node: ConceptNode, graph: ConceptGraph, onJumpToChapter: ((String) -> Void)?) {
        self.node = node
        self.graph = graph
        self.onJumpToChapter = onJumpToChapter
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing16) {
                    if let chapterId = node.introducedIn {
                        chapterBadge(chapterId: chapterId)
                    }

                    if let summary = node.summary {
                        Text(summary)
                            .font(.cfBody)
                            .foregroundStyle(Color.cfLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No summary available.")
                            .font(.cfBody)
                            .foregroundStyle(Color.cfSecondaryLabel)
                            .italic()
                    }

                    let prereqs = prerequisites(for: node.id)
                    if !prereqs.isEmpty {
                        Divider()
                        prerequisitesSection(prereqs)
                    }

                    if let chapterId = node.introducedIn, onJumpToChapter != nil {
                        Divider()
                        jumpButton(chapterId: chapterId)
                    }
                }
                .padding(.cfSpacing20)
            }
            .navigationTitle(node.label)
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func chapterBadge(chapterId: String) -> some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "book.pages")
                .font(.cfCaption)
                .foregroundStyle(Color.cfAccent)
            Text("Introduced in Chapter \(chapterId)")
                .font(.cfCaption)
                .foregroundStyle(Color.cfAccent)
        }
        .padding(.horizontal, .cfSpacing12)
        .padding(.vertical, .cfSpacing4)
        .background(Color.cfAccent.opacity(0.1), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func prerequisitesSection(_ prereqs: [ConceptNode]) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text("Prerequisites")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            ForEach(prereqs) { prereq in
                HStack(spacing: .cfSpacing8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfAccent)
                    Text(prereq.label)
                        .font(.cfCallout)
                        .foregroundStyle(Color.cfLabel)
                }
            }
        }
    }

    @ViewBuilder
    private func jumpButton(chapterId: String) -> some View {
        Button {
            dismiss()
            onJumpToChapter?(chapterId)
        } label: {
            Label("Go to Chapter \(chapterId)", systemImage: "arrow.up.right.circle")
                .font(.cfHeadline)
                .frame(maxWidth: .infinity)
                .padding(.cfSpacing16)
                .background(Color.cfAccent, in: RoundedRectangle(cornerRadius: .cfRadius12))
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to Chapter \(chapterId)")
    }

    // MARK: - Helpers

    private func prerequisites(for nodeId: String) -> [ConceptNode] {
        let prereqIds = graph.edges
            .filter { edge in
                guard case .prerequisite = edge.edgeType else { return false }
                return edge.to == nodeId
            }
            .map(\.from)

        return graph.concepts.filter { prereqIds.contains($0.id) }
    }
}
