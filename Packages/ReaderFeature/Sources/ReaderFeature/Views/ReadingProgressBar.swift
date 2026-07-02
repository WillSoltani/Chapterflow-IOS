import SwiftUI
import DesignSystem

/// A thin capsule progress bar pinned at the top of the reader screen.
///
/// Shows how far through the chapter the user has read, plus an estimated
/// time-remaining label when available. Updates fluidly as the user scrolls.
public struct ReadingProgressBar: View {
    /// Fraction complete (0…1).
    public let readPercent: Double
    /// Estimated minutes remaining, or `nil` when unavailable.
    public let timeLeftMinutes: Int?

    public init(readPercent: Double, timeLeftMinutes: Int?) {
        self.readPercent = readPercent
        self.timeLeftMinutes = timeLeftMinutes
    }

    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.cfSeparator.opacity(0.3))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.cfAccent)
                        .frame(width: max(0, geometry.size.width * readPercent), height: 3)
                        .animation(.linear(duration: 0.15), value: readPercent)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, .cfSpacing16)

            if let minutes = timeLeftMinutes, readPercent < 0.95 {
                HStack {
                    Spacer()
                    Text(timeLeftLabel(minutes: minutes))
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfTertiaryLabel)
                        .monospacedDigit()
                        .animation(.none, value: minutes)
                }
                .padding(.horizontal, .cfSpacing16)
                .padding(.top, 3)
            }
        }
        .padding(.top, .cfSpacing4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Helpers

    private func timeLeftLabel(minutes: Int) -> String {
        if minutes <= 0 { return "< 1 min left" }
        return minutes == 1 ? "1 min left" : "\(minutes) min left"
    }

    private var accessibilityLabel: String {
        let percent = Int(readPercent * 100)
        if let mins = timeLeftMinutes, mins > 0 {
            return "\(percent)% read, \(timeLeftLabel(minutes: mins))"
        }
        return "\(percent)% read"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Progress bar states") {
    VStack(spacing: .cfSpacing24) {
        Group {
            ReadingProgressBar(readPercent: 0, timeLeftMinutes: 12)
            ReadingProgressBar(readPercent: 0.25, timeLeftMinutes: 9)
            ReadingProgressBar(readPercent: 0.6, timeLeftMinutes: 4)
            ReadingProgressBar(readPercent: 0.85, timeLeftMinutes: 1)
            ReadingProgressBar(readPercent: 1.0, timeLeftMinutes: 0)
        }
        .background(Color.cfBackground)
    }
    .padding()
}
#endif
