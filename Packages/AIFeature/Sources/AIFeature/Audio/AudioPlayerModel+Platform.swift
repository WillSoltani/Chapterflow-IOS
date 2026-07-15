@preconcurrency import AVFoundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
extension AudioPlayerModel {
    func setupAudioSession() {
        #if canImport(UIKit)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: audio still works without background-session optimization.
        }
        #endif
    }

    #if canImport(UIKit)
    func makeArtworkImage(emoji: String?, colorHex: String?) -> UIImage? {
        let resolvedEmoji = emoji ?? "📚"
        let color = Color(hex: colorHex ?? "#3B82F6")
        let view = AudioArtworkView(emoji: resolvedEmoji, color: color)
            .frame(width: 600, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }
    #endif
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
