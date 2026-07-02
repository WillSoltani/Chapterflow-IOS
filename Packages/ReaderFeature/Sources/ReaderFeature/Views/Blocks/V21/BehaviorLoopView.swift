import SwiftUI
import DesignSystem
import Models

/// The v21 behavior-loop block: an interactive "which pattern fits you?" picker
/// that reveals the associated example or if-then plan when a reader archetype
/// is selected.
///
/// Each `ReaderPattern` maps to either an example (via `mapsToExampleIndex`)
/// or an if-then plan (via `mapsToPlanIndex`). Out-of-bounds indices are silently
/// ignored — tapping the chip still selects it but reveals nothing extra.
struct BehaviorLoopView: View {
    let loop: BehaviorLoop
    let examples: [ResolvedExample]
    let ifThenPlans: [ResolvedIfThenPlan]

    @State private var selectedPatternId: String?
    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            sectionHeader

            patternChips

            if let patternId = selectedPatternId,
               let pattern = loop.readerPatterns.first(where: { $0.id == patternId }) {
                revealedContent(for: pattern)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .animation(.easeInOut(duration: 0.22), value: selectedPatternId)
    }

    // MARK: - Header

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Label {
                Text("WHICH PATTERN FITS YOU?")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
                    .kerning(0.8)
            } icon: {
                Image(systemName: "person.2.wave.2")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
            }
            Text("Tap the pattern that sounds most like you.")
                .font(.cfFootnote)
                .foregroundStyle(appearance.colors.tertiaryText)
        }
    }

    // MARK: - Pattern Chips

    private var patternChips: some View {
        FlowLayout(spacing: .cfSpacing8) {
            ForEach(loop.readerPatterns, id: \.id) { pattern in
                PatternChipView(
                    label: pattern.label,
                    isSelected: selectedPatternId == pattern.id,
                    appearance: appearance
                ) {
                    if selectedPatternId == pattern.id {
                        selectedPatternId = nil
                    } else {
                        selectedPatternId = pattern.id
                    }
                }
            }
        }
    }

    // MARK: - Revealed Content

    @ViewBuilder
    private func revealedContent(for pattern: ReaderPattern) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Divider()
                .overlay(appearance.colors.separator)

            if let exIdx = pattern.mapsToExampleIndex,
               exIdx >= 0, exIdx < examples.count {
                let example = examples[exIdx]
                revealedExample(example)
            } else if let planIdx = pattern.mapsToPlanIndex,
                      planIdx >= 0, planIdx < ifThenPlans.count {
                let plan = ifThenPlans[planIdx]
                revealedPlan(plan)
            }
        }
    }

    @ViewBuilder
    private func revealedExample(_ example: ResolvedExample) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            if let title = example.title, !title.isEmpty {
                Text(title)
                    .font(.cfSubheadline)
                    .foregroundStyle(appearance.colors.accent)
            }
            Text(AttributedString.inlineMarkdown(example.scenario))
                .font(.cfBody)
                .foregroundStyle(appearance.colors.primaryText)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !example.whatToDo.isEmpty {
                VStack(alignment: .leading, spacing: .cfSpacing8) {
                    ForEach(Array(example.whatToDo.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: .cfSpacing12) {
                            Text("\(index + 1).")
                                .font(.cfCaption.monospacedDigit())
                                .foregroundStyle(appearance.colors.accent)
                                .frame(minWidth: 18, alignment: .leading)
                            Text(AttributedString.inlineMarkdown(step))
                                .font(.cfCallout)
                                .foregroundStyle(appearance.colors.primaryText)
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func revealedPlan(_ plan: ResolvedIfThenPlan) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack(alignment: .top, spacing: .cfSpacing12) {
                Text("If")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.tertiaryText)
                    .frame(minWidth: 18, alignment: .leading)
                Text(AttributedString.inlineMarkdown(plan.context))
                    .font(.cfCallout)
                    .foregroundStyle(appearance.colors.secondaryText)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: .cfSpacing12) {
                Text("Then")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.tertiaryText)
                    .frame(minWidth: 18, alignment: .leading)
                Text(AttributedString.inlineMarkdown(plan.plan))
                    .font(.cfBody)
                    .foregroundStyle(appearance.colors.primaryText)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("If \(plan.context), then \(plan.plan)")
    }
}

// MARK: - Pattern Chip

private struct PatternChipView: View {
    let label: String
    let isSelected: Bool
    let appearance: ReadingAppearance
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.cfCallout)
                .foregroundStyle(isSelected ? appearance.colors.pageBg : appearance.colors.primaryText)
                .padding(.horizontal, .cfSpacing12)
                .padding(.vertical, .cfSpacing8)
                .background(isSelected ? appearance.colors.accent : appearance.colors.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: .cfRadius8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Flow Layout (local copy for self-contained file)

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
