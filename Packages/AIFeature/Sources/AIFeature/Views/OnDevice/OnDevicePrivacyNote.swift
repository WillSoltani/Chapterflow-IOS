import SwiftUI
import DesignSystem

/// A subtle badge that communicates on-device, private inference.
///
/// Show this wherever on-device AI output is available — in empty states,
/// near generated content, or in chapter summary / highlight sheets.
/// It must never appear when on-device AI is unavailable or the feature flag is off.
struct OnDevicePrivacyNote: View {
    var body: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .medium))
            Text("Runs on your device · Private")
                .font(.cfCaption2)
        }
        .foregroundStyle(Color.cfSecondaryLabel)
        .padding(.horizontal, .cfSpacing10)
        .padding(.vertical, .cfSpacing4)
        .background(
            Capsule()
                .fill(Color.cfSecondaryFill)
        )
        .accessibilityLabel("Generated on your device — not sent to any server")
    }
}

private extension CGFloat {
    static let cfSpacing10: CGFloat = 10
}
