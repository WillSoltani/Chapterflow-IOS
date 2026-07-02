import SwiftUI
import DesignSystem

/// Wraps any reader block with annotation behaviour:
/// - Long-press (context menu) → Highlight / Note / Copy / Ask about this / My Highlights
/// - Active highlights for the current (variant, tone) → tinted background overlay
/// - Cross-variant highlights → `BlockAnnotationBadge` above the block
///
/// Uses block-level anchoring: the anchor always spans the full block text
/// (`startChar = 0, endChar = blockText.count`).  Character ranges survive
/// every font-size and theme change by construction.
struct AnnotatedBlock<Content: View>: View {
    let blockIndex: Int
    /// The plain-text representation of this block, used as the anchor snippet.
    let blockText: String
    /// The block type string stored in the anchor (e.g. "paragraph", "heading").
    let blockType: String
    let annotationModel: AnnotationModel
    /// Human-readable label for the active variant (used in badge display).
    let currentVariantLabel: String
    /// Human-readable label for the active tone (used in badge display).
    let currentToneLabel: String
    /// Called when the user taps the cross-variant badge to jump to that view.
    let onSwitchVariantTone: ((String, String) -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            crossVariantBadge
            blockContent
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var crossVariantBadge: some View {
        if let info = annotationModel.crossVariantInfo(forBlock: blockIndex) {
            let vk = info.variantKey
            let tk = info.toneKey
            BlockAnnotationBadge(
                count: info.count,
                variantLabel: variantLabel(for: vk),
                toneLabel: toneLabel(for: tk),
                onTap: { onSwitchVariantTone?(vk, tk) }
            )
            .padding(.bottom, .cfSpacing2)
        }
    }

    private var blockContent: some View {
        let highlights = annotationModel.activeHighlights(forBlock: blockIndex)
        let color = highlights.compactMap { $0.colorRaw }
            .compactMap { HighlightColor(rawValue: $0) }
            .first?.swiftUIColor

        return content()
            .background(color ?? .clear, in: RoundedRectangle(cornerRadius: .cfRadius4))
            .contextMenu {
                annotationMenuItems
            }
    }

    @ViewBuilder
    private var annotationMenuItems: some View {
        let highlights = annotationModel.activeHighlights(forBlock: blockIndex)
        let hasHighlight = !highlights.isEmpty

        if !blockText.isEmpty {
            Menu {
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        annotationModel.createHighlight(
                            blockIndex: blockIndex,
                            blockText: blockText,
                            blockType: blockType,
                            color: color
                        )
                    } label: {
                        Label(color.label, systemImage: "circle.fill")
                    }
                    .tint(color.solidColor)
                }
            } label: {
                Label(hasHighlight ? "Change colour" : "Highlight", systemImage: "highlighter")
            }

            if hasHighlight {
                Button(role: .destructive) {
                    for ann in highlights {
                        annotationModel.deleteAnnotation(ann)
                    }
                } label: {
                    Label("Remove highlight", systemImage: "highlighter")
                }
            }

            Button {
                annotationModel.beginAddingNote(
                    blockIndex: blockIndex,
                    blockText: blockText,
                    blockType: blockType
                )
            } label: {
                Label("Add Note", systemImage: "note.text")
            }

            Divider()

            Button {
#if os(iOS)
                UIPasteboard.general.string = blockText
#endif
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if annotationModel.onAskAboutSelection != nil {
                Button {
                    annotationModel.askAbout(blockText)
                } label: {
                    Label("Ask about this", systemImage: "sparkles")
                }
            }

            Divider()

            Button {
                annotationModel.isShowingAnnotationsList = true
            } label: {
                Label("My Highlights", systemImage: "list.bullet")
            }
        }
    }

    // MARK: - Helpers

    private func variantLabel(for raw: String) -> String {
        switch raw {
        case "easy":        return "Easy"
        case "medium":      return "Medium"
        case "hard":        return "Hard"
        case "precise":     return "Precise"
        case "balanced":    return "Balanced"
        case "challenging": return "Challenging"
        default:            return raw.capitalized
        }
    }

    private func toneLabel(for raw: String) -> String {
        switch raw {
        case "gentle":      return "Gentle"
        case "direct":      return "Direct"
        case "competitive": return "Competitive"
        default:            return raw.capitalized
        }
    }
}
