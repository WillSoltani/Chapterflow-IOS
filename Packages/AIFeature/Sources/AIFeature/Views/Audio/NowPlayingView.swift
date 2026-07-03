import SwiftUI
import Models
import DesignSystem

/// Full-screen Now Playing screen for chapter audio narration.
///
/// Presented as a `.fullScreenCover` from ``MiniPlayerBar``.
/// Bound to the same ``AudioPlayerModel`` instance that drives the mini-player.
public struct NowPlayingView: View {

    @Bindable var model: AudioPlayerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showSleepPicker = false

    public init(model: AudioPlayerModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                background
                content
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    dismissButton
                }
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        Group {
            if reduceTransparency {
                Color.cfBackground
            } else {
                Color.cfBackground.opacity(0.96)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                artworkSection
                    .padding(.top, .cfSpacing32)
                metadataSection
                    .padding(.top, .cfSpacing24)
                timelineSection
                    .padding(.top, .cfSpacing32)
                    .padding(.horizontal, .cfSpacing32)
                transportSection
                    .padding(.top, .cfSpacing24)
                accessoryRow
                    .padding(.top, .cfSpacing32)
                Spacer(minLength: .cfSpacing40)
            }
        }
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        Group {
            if let cover = model.currentItem?.cover {
                LargeCoverView(cover: cover)
                    .scaleEffect(model.isPlaying ? 1.0 : 0.88)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: model.isPlaying)
            } else {
                RoundedRectangle(cornerRadius: .cfRadius24, style: .continuous)
                    .fill(Color.cfSecondaryFill)
                    .frame(width: 260, height: 260)
                    .overlay {
                        Image(systemName: "headphones")
                            .font(.system(size: 80))
                            .foregroundStyle(Color.cfSecondaryLabel)
                    }
            }
        }
        .shadow(color: .black.opacity(0.20), radius: 24, x: 0, y: 8)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: .cfSpacing4) {
            Text(model.currentItem?.chapterTitle ?? "")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .cfSpacing32)

            Text(model.currentItem?.bookTitle ?? "")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        AudioTimeline(
            currentTime: model.currentTime,
            duration: model.duration,
            onSeek: { model.seek(to: $0) }
        )
    }

    // MARK: - Transport

    private var transportSection: some View {
        HStack(spacing: .cfSpacing40) {
            skipButton(seconds: -15, label: "15")
            playPauseButton
            skipButton(seconds: 15, label: "15")
        }
    }

    private var playPauseButton: some View {
        Button {
            model.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.cfAccent)
                    .frame(width: 72, height: 72)
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .offset(x: model.isPlaying ? 0 : 2) // optical centre for play triangle
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(seconds: Double, label: String) -> some View {
        Button {
            model.skip(seconds: seconds)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: seconds < 0 ? "gobackward" : "goforward")
                    .font(.system(size: 28, weight: .regular))
                Text(label)
                    .font(.cfCaption2)
            }
            .foregroundStyle(Color.cfLabel)
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Skip back 15 seconds" : "Skip forward 15 seconds")
    }

    // MARK: - Accessory row (speed + sleep timer + AirPlay)

    private var accessoryRow: some View {
        HStack(spacing: .cfSpacing32) {
            speedButton
            Spacer()
            sleepTimerButton
            Spacer()
            airPlayButton
        }
        .padding(.horizontal, .cfSpacing40)
    }

    private var speedButton: some View {
        Menu {
            ForEach([Float(0.75), 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                Button {
                    model.setPlaybackRate(rate)
                } label: {
                    Label(
                        speedLabel(for: rate),
                        systemImage: model.playbackRate == rate ? "checkmark" : ""
                    )
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "speedometer")
                    .font(.system(size: 22))
                Text(speedLabel(for: model.playbackRate))
                    .font(.cfCaption2)
            }
            .foregroundStyle(Color.cfLabel)
        }
        .accessibilityLabel("Playback speed: \(speedLabel(for: model.playbackRate))")
    }

    private var sleepTimerButton: some View {
        Menu {
            Button("Off") { model.setSleepTimer(minutes: nil) }
            ForEach([5, 10, 15, 30, 45, 60], id: \.self) { mins in
                Button("\(mins) minutes") { model.setSleepTimer(minutes: mins) }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 22))
                    .foregroundStyle(model.sleepTimerEndDate != nil ? Color.cfAccent : Color.cfLabel)
                Text(sleepTimerLabel)
                    .font(.cfCaption2)
                    .foregroundStyle(model.sleepTimerEndDate != nil ? Color.cfAccent : Color.cfLabel)
            }
        }
        .accessibilityLabel(sleepTimerLabel)
    }

    @ViewBuilder
    private var airPlayButton: some View {
        #if os(iOS)
        AirPlayButton()
            .frame(width: 44, height: 44)
        #else
        EmptyView()
        #endif
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.cfLabel)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Helpers

    private func speedLabel(for rate: Float) -> String {
        rate == 1.0 ? "1×" : String(format: rate.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f×" : "%.2g×", rate)
    }

    private var sleepTimerLabel: String {
        guard let end = model.sleepTimerEndDate else { return "Sleep" }
        let remaining = Int(max(0, end.timeIntervalSinceNow / 60))
        return "\(remaining)m"
    }
}

// MARK: - Large cover artwork

private struct LargeCoverView: View {
    let cover: Cover

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .cfRadius24, style: .continuous)
                .fill(coverColor)
            Text(cover.emoji ?? "📖")
                .font(.system(size: 160))
        }
        .frame(width: 260, height: 260)
    }

    private var coverColor: Color {
        guard let hex = cover.color else { return Color.cfAccent }
        return Color(hex: hex) ?? Color.cfAccent
    }
}

// MARK: - AirPlay route picker

#if os(iOS)
import AVKit

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Color.cfLabel)
        view.activeTintColor = UIColor(Color.cfAccent)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

// MARK: - Color hex helper (local to this file)

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
#Preview("Now Playing") {
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
    model.currentTime = 73
    model.duration = 312
    return NowPlayingView(model: model)
}

#Preview("Now Playing — paused") {
    let model = AudioPlayerModel(repository: FakeAudioRepository())
    model.currentItem = AudioPlaybackItem(
        bookId: "atomic-habits",
        bookTitle: "Atomic Habits",
        bookAuthor: "James Clear",
        chapterNumber: 1,
        chapterTitle: "The Surprising Power of Atomic Habits",
        cover: Cover(emoji: "⚛️", color: "#E85D04"),
        totalChapters: 12,
        audioURL: URL(string: "https://example.com/audio.m4a")!
    )
    model.isPlaying = false
    model.currentTime = 145
    model.duration = 410
    return NowPlayingView(model: model)
}
#endif
