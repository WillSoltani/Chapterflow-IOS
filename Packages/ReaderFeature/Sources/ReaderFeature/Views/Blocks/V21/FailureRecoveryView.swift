import SwiftUI
import DesignSystem
import Models

/// Renders a failure-recovery block: a normalising opener, a cue question,
/// a set of recovery options, and a repair line.
///
/// All four fields are required for the block to be emitted (all-or-nothing
/// contract enforced by `ReaderContentBuilder`). The options are displayed as
/// numbered items so readers can scan quickly.
struct FailureRecoveryView: View {
    let recovery: FailureRecovery

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            sectionHeader

            Text(AttributedString.inlineMarkdown(recovery.normalizingLine))
                .font(.system(size: bodyFontSize, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(appearance.colors.secondaryText)
                .lineSpacing(appearance.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .overlay(appearance.colors.separator)

            Text(AttributedString.inlineMarkdown(recovery.cueQuestion))
                .font(.cfSubheadline)
                .foregroundStyle(appearance.colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !recovery.options.isEmpty {
                VStack(alignment: .leading, spacing: .cfSpacing8) {
                    ForEach(Array(recovery.options.enumerated()), id: \.offset) { index, option in
                        HStack(alignment: .top, spacing: .cfSpacing12) {
                            Text("\(index + 1).")
                                .font(.cfCaption.monospacedDigit())
                                .foregroundStyle(appearance.colors.accent)
                                .frame(minWidth: 20, alignment: .leading)
                            Text(AttributedString.inlineMarkdown(option))
                                .font(.cfBody)
                                .foregroundStyle(appearance.colors.primaryText)
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Divider()
                .overlay(appearance.colors.separator)

            HStack(alignment: .top, spacing: .cfSpacing12) {
                Image(systemName: "arrow.uturn.right")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
                    .padding(.top, 2)
                Text(AttributedString.inlineMarkdown(recovery.repairLine))
                    .font(.cfCallout)
                    .foregroundStyle(appearance.colors.primaryText)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var sectionHeader: some View {
        Label {
            Text("WHEN YOU GET STUCK")
                .font(.cfCaption)
                .foregroundStyle(appearance.colors.accent)
                .kerning(0.8)
        } icon: {
            Image(systemName: "bandage")
                .font(.cfCaption)
                .foregroundStyle(appearance.colors.accent)
        }
    }

    private var accessibilityDescription: String {
        let optionsList = recovery.options
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: ". ")
        return "When you get stuck. \(recovery.normalizingLine). \(recovery.cueQuestion). Options: \(optionsList). \(recovery.repairLine)"
    }

    @ScaledMetric(relativeTo: .body) private var bodyFontSize: CGFloat = 17
}
