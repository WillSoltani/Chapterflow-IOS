import SwiftUI
import Models
import DesignSystem
import Persistence

/// Renders a resolved chapter as a full-page reading flow.
///
/// Builds the block array once at init from the given `ResolvedChapter`, then
/// renders each `ReaderBlock` in order inside a lazy scroll view. No raw
/// `ToneKeyed` values or variant keys reach this layer — all content has
/// already been collapsed by `ChapterContentResolver`.
///
/// Supply `AppPreferences` to have theme, font scale, and line spacing applied
/// reactively. The appearance tokens flow down through the SwiftUI environment
/// so every block view updates instantly when preferences change.
///
/// Use `ReaderControlSurface` when you need auto-hiding controls, depth/tone
/// switching, focus mode, or paginated reading.
public struct ReaderContentView: View {
    private let blocks: [ReaderBlock]
    private let preferences: AppPreferences?

    /// Initialise from a fully-resolved chapter with user preferences.
    public init(chapter: ResolvedChapter, preferences: AppPreferences? = nil) {
        self.blocks = ReaderContentBuilder().build(from: chapter)
        self.preferences = preferences
    }

    public var body: some View {
        // Computed here (inside `body`, which is @MainActor) so that accessing
        // AppPreferences's @MainActor-isolated properties is valid.
        let appearance = preferences.map { ReadingAppearance(preferences: $0) } ?? .default
        ScrollView {
            ReaderBlockListView(blocks: blocks, appearance: appearance)
        }
        .background(appearance.colors.pageBg)
        .readerAppearance(appearance)
    }
}
