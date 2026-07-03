import SwiftUI
import DesignSystem
import Persistence

/// A persistent mini-player bar shown above the tab bar whenever audio is active.
///
/// Survives navigation changes because it is owned by the root tab view, not
/// by individual feature screens. Tapping the bar opens `NowPlayingView`.
public struct MiniPlayerBar: View {

    @Environment(AudioPlayerModel.self) private var model
    @State private var showNowPlaying = false

    public init() {}

    public var body: some View {
        if model.showMiniPlayer {
            bar
        }
    }

    private var bar: some View {
        Button {
            showNowPlaying = true
        } label: {
            HStack(spacing: .cfSpacing12) {
                // Micro artwork
                let emoji = model.plan?.coverEmoji ?? "📚"
                let hex = model.plan?.coverColor ?? "#3B82F6"
                AudioArtworkView(
                    emoji: emoji,
                    color: Color(hex: hex),
                    size: 40
                )
                .clipShape(RoundedRectangle(cornerRadius: .cfRadius8))

                // Titles
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.plan?.chapterTitle ?? "")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(1)
                    Text(model.plan?.bookTitle ?? "")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .lineLimit(1)
                }

                Spacer()

                // Progress indicator (thin ring)
                let fraction = model.timeline.fraction(at: model.currentGlobalTime)
                ZStack {
                    Circle()
                        .stroke(Color.cfSeparator, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.cfAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

                // Play/pause
                Button {
                    Task { await model.togglePlayPause() }
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.cfLabel)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing8)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Audio player — \(model.plan?.chapterTitle ?? ""). Tap to open.")
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environment(model)
        }
        #endif
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Previews

#Preview("Mini player — playing") {
    let model = AudioPlayerModel(
        player: AudioPlayer(repository: FakeAudioRepository()),
        preferences: AppPreferences()
    )
    VStack {
        Spacer()
        MiniPlayerBar()
            .environment(model)
    }
    .background(Color.cfBackground)
}

#Preview("Mini player — dark") {
    let model = AudioPlayerModel(
        player: AudioPlayer(repository: FakeAudioRepository()),
        preferences: AppPreferences()
    )
    VStack {
        Spacer()
        MiniPlayerBar()
            .environment(model)
    }
    .background(Color.cfBackground)
    .preferredColorScheme(.dark)
}
