import SwiftUI

/// A token-driven segmented control with an animated selection pill and
/// selection haptic. Generic over any `Hashable` value; each segment supplies a
/// label. Built on `matchedGeometryEffect` for a smooth sliding indicator that
/// is gated by Reduce Motion.
public struct SegmentedControl<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    @Binding private var selection: Value
    private let options: [Value]
    private let label: (Value) -> LocalizedStringKey

    public init(
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> LocalizedStringKey
    ) {
        self._selection = selection
        self.options = options
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    Haptics.selection()
                    withAnimation(DSMotion.gated(DSMotion.snappySpring, reduceMotion: reduceMotion)) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(DSTypography.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.vertical, DSSpacing.xs)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                                    .fill(DSColor.surfaceElevated)
                                    .dsShadow(.subtle)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(DSSpacing.xs)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
    }
}

private enum DepthPreviewOption: String, CaseIterable, Hashable {
    case easy, medium, hard
}

#Preview("SegmentedControl", traits: .sizeThatFitsLayout) {
    @Previewable @State var selection: DepthPreviewOption = .medium
    return DSPreviewMatrix {
        SegmentedControl(
            selection: $selection,
            options: DepthPreviewOption.allCases,
            label: { LocalizedStringKey($0.rawValue.capitalized) }
        )
        .padding(DSSpacing.md)
    }
}
