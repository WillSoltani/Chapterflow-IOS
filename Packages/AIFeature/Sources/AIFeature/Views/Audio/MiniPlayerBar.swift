import SwiftUI
import Models
import DesignSystem

/// A compact, floating audio player bar that sits above the tab bar.
///
/// Mounted via `.safeAreaInset(edge: .bottom)` on the `TabView` in `AppRootView`.
/// Tapping the bar (anywhere except the play/pause button) opens ``NowPlayingView``.
///
/// Shows only when `model.hasActiveItem` — call sites gate visibility so no gap
/// appears when nothing is playing.
public struct MiniPlayerBar: View {

    @Bindable var model: AudioPlayerModel
    @State private var showNowPlaying = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(model: AudioPlayerModel) {
        self.model = model
    }

    public var body: some View {
        #if os(iOS)
        bar
            .fullScreenCover(isPresented: $showNowPlaying) {
                NowPlayingView(model: model)
            }
        #else
        bar
        #endif
    }

    // MARK: - Bar

    private var bar: some View {
        Button {
            showNowPlaying = true
        } label: {
            HStack(spacing: .cfSpacing12) {
                coverThumb
                titleStack
                Spacer(minLength: 0)
                playPauseButton
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing12)
            .background(barBackground, in: RoundedRectangle(cornerRadius: .cfRadius16, style: .continuous))
            .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.10), radius: 12, x: 0, y: 4)
            .padding(.horizontal, .cfSpacing12)
            .padding(.bottom, .cfSpacing8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap to open Now Playing")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Cover thumbnail

    @ViewBuilder
    private var coverThumb: some View {
        if let cover = model.currentItem?.cover {
            BookCoverThumb(cover: cover, size: 40)
        } else {
            RoundedRectangle(cornerRadius: .cfRadius8, style: .continuous)
                .fill(Color.cfSecondaryFill)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "headphones")
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
        }
    }

    // MARK: - Title stack

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.currentItem?.chapterTitle ?? "")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfLabel)
                .lineLimit(1)

            Text(model.currentItem?.bookTitle ?? "")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .lineLimit(1)
        }
    }

    // MARK: - Play / pause button

    private var playPauseButton: some View {
        Button {
            model.togglePlayPause()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.cfLabel)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
    }

    // MARK: - Background

    private var barBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        guard let item = model.currentItem else { return "Audio player" }
        let state = model.isPlaying ? "Playing" : "Paused"
        return "\(state): \(item.chapterTitle) from \(item.bookTitle)"
    }
}

// MARK: - Book cover thumbnail

/// A 40×40 rounded cover tile rendered from emoji + color. Shared with MiniPlayerBar
/// and NowPlayingView's compact layout.
struct BookCoverThumb: View {

    let cover: Cover
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(coverColor)

            Text(cover.emoji ?? "📖")
                .font(.system(size: size * 0.55))
        }
        .frame(width: size, height: size)
    }

    private var coverColor: Color {
        guard let hex = cover.color else { return Color.cfAccent }
        return Color(hex: hex) ?? Color.cfAccent
    }
}

// MARK: - Color hex helper

private extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Mini Player — playing") {
    let model = AudioPlayerModel(repository: FakeAudioRepository())
    model.currentItem = AudioPlaybackItem(
        bookId: "atomic-habits",
        bookTitle: "Atomic Habits",
        bookAuthor: "James Clear",
        chapterNumber: 3,
        chapterTitle: "How to Build Better Habits in 4 Simple Steps",
        cover: Cover(emoji: "⚛️", color: "#3366CC"),
        totalChapters: 12,
        audioURL: URL(string: "https://example.com/audio.m4a")!
    )
    model.isPlaying = true
    return VStack {
        Spacer()
        MiniPlayerBar(model: model)
    }
    .background(Color.cfBackground)
}

#Preview("Mini Player — paused") {
    let model = AudioPlayerModel(repository: FakeAudioRepository())
    model.currentItem = AudioPlaybackItem(
        bookId: "atomic-habits",
        bookTitle: "Atomic Habits",
        bookAuthor: "James Clear",
        chapterNumber: 1,
        chapterTitle: "The Surprising Power of Atomic Habits",
        cover: Cover(emoji: "⚛️", color: "#3366CC"),
        totalChapters: 12,
        audioURL: URL(string: "https://example.com/audio.m4a")!
    )
    model.isPlaying = false
    return VStack {
        Spacer()
        MiniPlayerBar(model: model)
    }
    .background(Color.cfBackground)
}
#endif
