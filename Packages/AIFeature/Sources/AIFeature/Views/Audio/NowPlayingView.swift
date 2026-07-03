@preconcurrency import AVKit
import SwiftUI
import DesignSystem
import Persistence

/// Full-screen Now Playing view for the audio narration player.
///
/// Shows artwork, chapter info, gapless scrubber, transport controls,
/// speed, sleep timer, and AirPlay. Presented as a sheet from the
/// ``MiniPlayerBar``.
public struct NowPlayingView: View {

    // MARK: - Dependencies

    @Environment(AudioPlayerModel.self) private var model

    // MARK: - Local state

    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    @State private var isDraggingSlider = false
    @State private var dragTime: Double = 0

    public init() {}

    // MARK: - View

    public var body: some View {
        ZStack {
            // Background — blurred tint from cover color.
            coverBackground

            ScrollView {
                VStack(spacing: 0) {
                    // Drag handle
                    dragHandle

                    // Artwork
                    artworkSection
                        .padding(.top, .cfSpacing24)
                        .padding(.bottom, .cfSpacing20)

                    // Chapter info
                    metaSection
                        .padding(.horizontal, .cfSpacing24)
                        .padding(.bottom, .cfSpacing24)

                    // Scrubber
                    scrubberSection
                        .padding(.horizontal, .cfSpacing24)
                        .padding(.bottom, .cfSpacing24)

                    // Transport controls
                    transportControls
                        .padding(.horizontal, .cfSpacing24)
                        .padding(.bottom, .cfSpacing32)

                    // Accessories: speed, sleep, AirPlay
                    accessoryRow
                        .padding(.horizontal, .cfSpacing24)
                        .padding(.bottom, .cfSpacing32)
                }
            }
        }
        .sheet(isPresented: $showSpeedPicker) {
            SpeedPickerView(selectedRate: Binding(
                get: { model.rate },
                set: { newRate in Task { await model.setRate(newRate) } }
            ))
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet(
                selected: Binding(
                    get: { model.sleepTimer },
                    set: { opt in Task { await model.setSleepTimer(opt) } }
                ),
                onDismiss: { showSleepTimer = false }
            )
        }
    }

    // MARK: - Subviews

    private var coverBackground: some View {
        Rectangle()
            .fill(Color.cfSecondaryBackground)
            .ignoresSafeArea()
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.cfTertiaryLabel.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, .cfSpacing12)
            .accessibilityHidden(true)
    }

    private var artworkSection: some View {
        let emoji = model.plan?.coverEmoji ?? "📚"
        let hex = model.plan?.coverColor ?? "#3B82F6"
        return AudioArtworkView(
            emoji: emoji,
            color: Color(hex: hex),
            size: 240
        )
        .scaleEffect(model.isPlaying ? 1.0 : 0.92)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.isPlaying)
        .accessibilityHidden(true)
    }

    private var metaSection: some View {
        VStack(spacing: .cfSpacing4) {
            Text(model.plan?.chapterTitle ?? "Chapter \(model.plan?.chapterNumber ?? 1)")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(model.plan?.bookTitle ?? "")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
    }

    private var scrubberSection: some View {
        VStack(spacing: .cfSpacing8) {
            // Progress slider
            Slider(
                value: Binding(
                    get: {
                        isDraggingSlider ? dragTime : model.currentGlobalTime
                    },
                    set: { newVal in
                        isDraggingSlider = true
                        dragTime = newVal
                    }
                ),
                in: 0...max(model.timeline.totalDuration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        let target = dragTime
                        Task { await model.seek(to: target) }
                        isDraggingSlider = false
                    }
                }
            )
            .tint(Color.cfAccent)
            .accessibilityLabel("Chapter progress")
            .accessibilityValue(formatTime(model.currentGlobalTime))

            // Time labels
            HStack {
                Text(formatTime(isDraggingSlider ? dragTime : model.currentGlobalTime))
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .monospacedDigit()
                Spacer()
                Text("-\(formatTime(model.timeline.totalDuration - model.currentGlobalTime))")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .monospacedDigit()
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: .cfSpacing40) {
            // Skip back 15s
            Button {
                Task { await model.skipBackward() }
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.cfLabel)
            }
            .accessibilityLabel("Skip back 15 seconds")

            // Play / Pause
            Button {
                Task { await model.togglePlayPause() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.cfAccent)
                        .frame(width: 72, height: 72)
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                        .offset(x: model.isPlaying ? 0 : 2)
                }
            }
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            // Skip forward 15s
            Button {
                Task { await model.skipForward() }
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.cfLabel)
            }
            .accessibilityLabel("Skip forward 15 seconds")
        }
    }

    private var accessoryRow: some View {
        HStack(spacing: .cfSpacing32) {
            // Speed
            Button {
                showSpeedPicker = true
            } label: {
                Text(model.rate.formattedSpeed)
                    .font(.cfSubheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.cfLabel)
                    .padding(.horizontal, .cfSpacing12)
                    .padding(.vertical, .cfSpacing8)
                    .background(Color.cfSecondaryBackground, in: Capsule())
            }
            .accessibilityLabel("Playback speed: \(model.rate.formattedSpeed)")

            Spacer()

            // Sleep timer
            Button {
                showSleepTimer = true
            } label: {
                Image(systemName: model.sleepTimer == .off ? "moon" : "moon.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(model.sleepTimer == .off ? Color.cfSecondaryLabel : Color.cfAccent)
            }
            .accessibilityLabel(model.sleepTimer == .off ? "Sleep timer off" : "Sleep timer: \(model.sleepTimer.displayName)")

            // AirPlay
            #if canImport(UIKit)
            AirPlayButton()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
            #endif
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - AirPlay route picker

#if canImport(UIKit)
/// Wraps `AVRoutePickerView` for SwiftUI.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Color.cfLabel)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor(Color.cfLabel)
    }
}
#endif

// MARK: - Helpers

private extension Float {
    var formattedSpeed: String {
        self == 1.0 ? "1×" : "\(String(format: "%g", self))×"
    }
}

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

#Preview("Now Playing — loading") {
    let model = AudioPlayerModel(
        player: AudioPlayer(repository: FakeAudioRepository()),
        preferences: AppPreferences()
    )
    NowPlayingView()
        .environment(model)
}

#Preview("Now Playing — dark") {
    let model = AudioPlayerModel(
        player: AudioPlayer(repository: FakeAudioRepository()),
        preferences: AppPreferences()
    )
    NowPlayingView()
        .environment(model)
        .preferredColorScheme(.dark)
}
