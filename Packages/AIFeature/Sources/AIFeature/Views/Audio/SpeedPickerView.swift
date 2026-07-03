import SwiftUI
import DesignSystem

/// Compact speed selector — 0.75×, 1×, 1.25×, 1.5×, 1.75×, 2×.
struct SpeedPickerView: View {
    @Binding var selectedRate: Float

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Playback Speed")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
                .padding(.horizontal, .cfSpacing20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: .cfSpacing12) {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        selectedRate = speed
                    } label: {
                        Text(speed.formatted)
                            .font(.cfSubheadline)
                            .fontWeight(selectedRate == speed ? .bold : .regular)
                            .foregroundStyle(selectedRate == speed ? Color.white : Color.cfLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, .cfSpacing12)
                            .background(
                                RoundedRectangle(cornerRadius: .cfRadius12)
                                    .fill(selectedRate == speed ? Color.cfAccent : Color.cfSecondaryBackground)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(speed.formatted) speed")
                    .accessibilityAddTraits(selectedRate == speed ? .isSelected : [])
                }
            }
            .padding(.horizontal, .cfSpacing20)
        }
        .padding(.vertical, .cfSpacing20)
    }
}

private extension Float {
    var formatted: String {
        self == 1.0 ? "1×" : "\(String(format: "%g", self))×"
    }
}

#Preview("Speed picker") {
    SpeedPickerView(selectedRate: .constant(1.0))
        .background(Color.cfBackground)
}
