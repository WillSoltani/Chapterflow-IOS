import AppIntents
import SwiftUI
import DesignSystem

// MARK: - ChapterFlowShortcuts

/// Registers ChapterFlow's Siri Shortcuts so they appear in the Shortcuts app
/// and are surfaced as Siri suggestions on the lock screen and in Spotlight.
///
/// Phrases use `\(.applicationName)` so the system inserts the correct
/// localised app name at runtime. Call ``IntentDonationManager/update()``
/// whenever state changes that make a shortcut more relevant.
struct ChapterFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDailyReadingIntent(),
            phrases: [
                "Start my daily reading with \(.applicationName)",
                "Open my reading in \(.applicationName)",
                "Continue reading in \(.applicationName)",
                "Resume my book in \(.applicationName)",
            ],
            shortTitle: "Start Reading",
            systemImageName: "book.fill"
        )
        AppShortcut(
            intent: StartReviewIntent(),
            phrases: [
                "Review now with \(.applicationName)",
                "Start my reviews in \(.applicationName)",
                "Do my reviews in \(.applicationName)",
            ],
            shortTitle: "Review Now",
            systemImageName: "star.fill"
        )
        AppShortcut(
            intent: StartAudioNarrationIntent(),
            phrases: [
                "Read with \(.applicationName)",
                "Listen to my book with \(.applicationName)",
                "Start narration with \(.applicationName)",
                "Play audio in \(.applicationName)",
            ],
            shortTitle: "Listen to Chapter",
            systemImageName: "headphones"
        )
        AppShortcut(
            intent: LogDailyReadingIntent(),
            phrases: [
                "Log my reading in \(.applicationName)",
                "Log today's reading with \(.applicationName)",
                "Record reading time in \(.applicationName)",
            ],
            shortTitle: "Log Reading",
            systemImageName: "checkmark.circle.fill"
        )
    }
}

// MARK: - IntentDonationManager

/// Re-registers App Shortcuts with the system. Idempotent — safe to call on every launch.
///
/// Calling this after state changes (new continue-reading record, new due reviews) lets
/// Siri surface contextually relevant suggestions proactively.
public enum IntentDonationManager {
    @MainActor
    public static func update() {
        ChapterFlowShortcuts.updateAppShortcutParameters()
    }
}

// MARK: - Preview

/// Design-review aid: shows the four Siri shortcut tiles so we can verify
/// icons, titles, and descriptions without launching the Shortcuts app.
private struct ShortcutsPreviewView: View {
    private struct ShortcutTile: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let accent: Color
    }

    private let tiles: [ShortcutTile] = [
        .init(title: "Start Reading", subtitle: "Opens ChapterFlow at your last chapter",
              icon: "book.fill", accent: .cfAccent),
        .init(title: "Review Now", subtitle: "Opens a spaced-repetition review session",
              icon: "star.fill", accent: .yellow),
        .init(title: "Listen to Chapter", subtitle: "Starts audio narration of your chapter",
              icon: "headphones", accent: .purple),
        .init(title: "Log Reading", subtitle: "Records reading minutes for today",
              icon: "checkmark.circle.fill", accent: .green),
    ]

    var body: some View {
        NavigationStack {
            List(tiles) { tile in
                HStack(spacing: .cfSpacing12) {
                    Image(systemName: tile.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(tile.accent, in: RoundedRectangle(cornerRadius: .cfRadius8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tile.title)
                            .font(.cfBody)
                        Text(tile.subtitle)
                            .font(.cfFootnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("ChapterFlow Shortcuts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

#Preview("Shortcuts — light") {
    ShortcutsPreviewView()
}

#Preview("Shortcuts — dark") {
    ShortcutsPreviewView()
        .preferredColorScheme(.dark)
}

#Preview("Shortcuts — XXL type") {
    ShortcutsPreviewView()
        .dynamicTypeSize(.accessibility3)
}
