import SwiftUI

/// A full-screen confetti celebration overlay.
///
/// Show it over content to celebrate a user achievement (e.g., passing a quiz).
/// The animation runs for ~2.5 s then stops automatically. The view is
/// non-interactive and hidden from VoiceOver.
///
/// ```swift
/// ZStack {
///     contentView
///     CFConfetti(isActive: didPass)
/// }
/// ```
public struct CFConfetti: View {
    public let isActive: Bool

    @State private var launchDate: Date?

    private static let duration: TimeInterval = 2.5
    private static let count = 52

    public init(isActive: Bool) { self.isActive = isActive }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: launchDate == nil)) { tl in
            Canvas { context, size in
                guard let launch = launchDate else { return }
                let elapsed = tl.date.timeIntervalSince(launch)
                guard elapsed < Self.duration else { return }
                for i in 0..<Self.count {
                    context.drawLayer { ctx in
                        Self.drawPiece(
                            index: i,
                            elapsed: elapsed,
                            duration: Self.duration,
                            size: size,
                            context: &ctx
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .onChange(of: isActive) { _, active in
            launchDate = active ? Date() : nil
        }
        .onAppear {
            if isActive { launchDate = Date() }
        }
    }

    private static func drawPiece(
        index: Int,
        elapsed: Double,
        duration: Double,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        let seed = Double(index)
        let delay = (seed.truncatingRemainder(dividingBy: 8)) * 0.09
        let progress = max(0, min(1, (elapsed - delay) / max(duration - delay, 0.001)))
        guard progress > 0 else { return }

        let startX = (seed * 73 + 31).truncatingRemainder(dividingBy: max(size.width, 1))
        let drift = ((seed * 41 + 13).truncatingRemainder(dividingBy: 90)) - 45
        let x = startX + drift * sin(progress * .pi)
        let y = progress * (size.height + 80) - 40
        let rotations = (seed.truncatingRemainder(dividingBy: 5)) + 1
        let angle = Angle(degrees: progress * rotations * 270)
        let opacity = progress < 0.75 ? 1.0 : 1.0 - (progress - 0.75) / 0.25

        let palette: [Color] = [.cfAccent, .yellow, .pink, .orange, .green, .purple, .cyan, .red]
        let color = palette[index % palette.count]

        context.opacity = opacity
        context.translateBy(x: x, y: y)
        context.rotate(by: angle)

        if index % 3 == 0 {
            context.fill(
                Path(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8)),
                with: .color(color)
            )
        } else {
            context.fill(
                Path(CGRect(x: -4, y: -3, width: 8, height: 6)),
                with: .color(color)
            )
        }
    }
}

// MARK: - Preview

#Preview("CFConfetti — active") {
    ZStack {
        Color.cfGroupedBackground.ignoresSafeArea()
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.cfAccent)
            Text("Chapter 1 Passed!")
                .font(.cfTitle1)
        }
        CFConfetti(isActive: true)
    }
}

#Preview("CFConfetti — dark") {
    ZStack {
        Color.cfGroupedBackground.ignoresSafeArea()
        Text("Well done!").font(.cfTitle1)
        CFConfetti(isActive: true)
    }
    .preferredColorScheme(.dark)
}
