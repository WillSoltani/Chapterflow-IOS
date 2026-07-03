import SwiftUI
import DesignSystem

/// Renders an emoji+color gradient cover as the Now Playing artwork.
///
/// Used both in the `NowPlayingView` and to generate the `MPMediaItemArtwork`
/// image for the lock screen / Control Center.
public struct AudioArtworkView: View {
    public let emoji: String
    public let color: Color
    public var size: CGFloat = 280

    public init(emoji: String, color: Color, size: CGFloat = 280) {
        self.emoji = emoji
        self.color = color
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.85), color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(emoji)
                .font(.system(size: size * 0.42))
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.4), radius: size * 0.08, y: size * 0.06)
        .accessibilityLabel("Cover art")
    }
}

#if canImport(UIKit)
#Preview("Artwork — light") {
    AudioArtworkView(emoji: "⚛️", color: Color(red: 0.23, green: 0.51, blue: 0.96))
        .padding(.cfSpacing32)
}

#Preview("Artwork — dark") {
    AudioArtworkView(emoji: "🏔️", color: Color(red: 0.16, green: 0.60, blue: 0.44))
        .padding(.cfSpacing32)
        .preferredColorScheme(.dark)
}
#endif
