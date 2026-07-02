import Foundation
import Observation
import Models
import Persistence

/// Manages the interactive state of the reader control surface.
///
/// Owns the active depth variant and tone selection, re-resolves chapter
/// content instantly via `ChapterContentResolver` on every switch (no network
/// required), and persists selections per-book via `BookReadingPreferences`.
///
/// `pendingScrollAnchor` is set to the saved block index each time content
/// is rebuilt; the hosting scroll view consumes it to restore position.
@Observable
@MainActor
public final class ReaderControlsModel {

    // MARK: - Configuration (not observed)

    @ObservationIgnored private let chapter: Chapter
    public let bookId: String
    public let variantFamily: VariantFamily
    @ObservationIgnored public let preferences: AppPreferences
    @ObservationIgnored private let store: KeyValueStore
    @ObservationIgnored private let resolver: ChapterContentResolver
    @ObservationIgnored private let builder: ReaderContentBuilder

    // MARK: - Content state

    /// The ordered block array for the current depth and tone selection.
    public private(set) var blocks: [ReaderBlock]

    /// The fully-resolved chapter for the current depth and tone selection.
    public private(set) var resolvedChapter: ResolvedChapter

    // MARK: - Selection state

    /// The user's active depth variant.
    /// Use `switchVariant(_:currentTopIndex:)` to change it.
    public private(set) var selectedVariant: VariantKey

    /// The user's active tone.
    /// Use `switchTone(_:currentTopIndex:)` to change it.
    public private(set) var selectedTone: ToneKey

    // MARK: - UI state

    /// Whether the control toolbar is currently visible.
    public var isToolbarVisible = true

    /// Whether focus mode (chrome-hidden reading) is active.
    public var isFocusModeActive = false

    /// The current reading mode (continuous scroll or paginated).
    public var readingMode: ReadingMode = .scroll

    /// Whether the appearance panel sheet is currently presented.
    public var isAppearancePanelPresented = false

    // MARK: - Scroll restoration

    /// Set by `switchVariant` and `switchTone` after blocks are rebuilt.
    /// The view should scroll to this index (already clamped to the new
    /// block count) and then call `clearPendingAnchor()`.
    public var pendingScrollAnchor: Int?

    // MARK: - Scroll progress tracking

    /// The index of the topmost visible block in the scroll view.
    /// Updated by `ReaderControlSurface` on every scroll-position change.
    /// Used to compute `readPercent` and detect chapter end.
    public var currentTopBlockIndex: Int = 0

    /// Fraction of the chapter read (0…1), derived from scroll position.
    /// Anchored on block indices so it survives font-size and theme changes.
    public var readPercent: Double {
        guard !blocks.isEmpty else { return 0 }
        // When the last block is the topmost visible item, percent = 1.0.
        return min(1.0, Double(currentTopBlockIndex + 1) / Double(blocks.count))
    }

    /// Estimated minutes of reading remaining, or `nil` when unavailable.
    /// Computed from the chapter's declared reading time and current progress.
    public var timeLeftMinutes: Int? {
        let total = resolvedChapter.readingTimeMinutes
        guard total > 0 else { return nil }
        let remaining = Double(total) * (1.0 - readPercent)
        return max(0, Int(remaining.rounded()))
    }

    // MARK: - Depth hint (filled by P6.4)

    /// The server-recommended depth variant for this reader.
    /// `nil` hides the hint slot. Set by the host after loading
    /// `GET /book/me/books/{bookId}/depth-recommendation`.
    public var recommendedVariant: VariantKey?

    // MARK: - Init

    /// Creates a model for the given chapter.
    ///
    /// - Parameters:
    ///   - chapter: The fully-loaded chapter with all `contentVariants`.
    ///   - bookId: Used to key per-book preference storage.
    ///   - variantFamily: Determines which depth labels are shown.
    ///   - preferences: Global reading preferences (appearance defaults).
    ///   - store: Key-value store for per-book persistence.
    public init(
        chapter: Chapter,
        bookId: String,
        variantFamily: VariantFamily,
        preferences: AppPreferences,
        store: KeyValueStore = KeyValueStore()
    ) {
        self.chapter = chapter
        self.bookId = bookId
        self.variantFamily = variantFamily
        self.preferences = preferences
        self.store = store
        self.resolver = ChapterContentResolver()
        self.builder = ReaderContentBuilder()

        // Per-book saved prefs take priority; fall back to global prefs.
        let saved = store.value(
            BookReadingPreferences.self,
            forKey: BookReadingPreferences.storageKey(for: bookId)
        )
        let initVariant: VariantKey
        let initTone: ToneKey
        if let saved {
            // DepthVariant / ReadingTone rawValues match VariantKey / ToneKey rawValues.
            initVariant = VariantKey(rawValue: saved.variantKeyRaw)
            initTone = ToneKey(rawValue: saved.toneKeyRaw)
        } else {
            initVariant = VariantKey(rawValue: preferences.depthVariant.rawValue)
            initTone = ToneKey(rawValue: preferences.readingTone.rawValue)
        }

        let resolved = ChapterContentResolver().resolve(
            chapter: chapter,
            selectedVariant: initVariant,
            selectedTone: initTone
        )

        self.selectedVariant = initVariant
        self.selectedTone = initTone
        self.resolvedChapter = resolved
        self.blocks = ReaderContentBuilder().build(from: resolved)
    }

    // MARK: - Switching depth / tone

    /// Switches to a new depth variant, preserving the reader's scroll position.
    ///
    /// Content is re-resolved synchronously from in-memory variant data —
    /// no network call is made. Sets `pendingScrollAnchor` for the view to
    /// consume after the block array is laid out.
    ///
    /// - Parameters:
    ///   - newVariant: The variant to switch to. No-op if already selected
    ///     or if the variant is `.unknown`.
    ///   - currentTopIndex: The block index at the top of the scroll view.
    public func switchVariant(_ newVariant: VariantKey, currentTopIndex: Int) {
        guard newVariant != selectedVariant, !newVariant.isUnknown else { return }
        selectedVariant = newVariant
        rebuildContent(preservingTopIndex: currentTopIndex)
        persistPreferences()
    }

    /// Switches to a new tone, preserving the reader's scroll position.
    ///
    /// Content is re-resolved synchronously — no network call is made.
    /// Block structure is identical across tone switches; the text content
    /// changes in place and SwiftUI preserves scroll position naturally.
    /// `pendingScrollAnchor` is still set for the paginated mode.
    ///
    /// - Parameters:
    ///   - newTone: The tone to switch to. No-op if already selected or `.unknown`.
    ///   - currentTopIndex: The block index at the top of the scroll view.
    public func switchTone(_ newTone: ToneKey, currentTopIndex: Int) {
        guard newTone != selectedTone, !newTone.isUnknown else { return }
        selectedTone = newTone
        rebuildContent(preservingTopIndex: currentTopIndex)
        persistPreferences()
    }

    // MARK: - UI actions

    /// Toggles the toolbar visibility.
    /// Wrap the call in `withAnimation` from the view for a smooth slide/fade.
    public func toggleToolbar() {
        isToolbarVisible.toggle()
    }

    /// Toggles focus mode (hides all reading chrome).
    ///
    /// Entering focus mode also hides the toolbar. Exiting restores it.
    /// The host view should apply `.statusBarHidden(model.isFocusModeActive)`
    /// and hide the navigation bar for full chrome removal.
    /// Wrap the call in `withAnimation` from the view for a smooth transition.
    public func toggleFocusMode() {
        isFocusModeActive.toggle()
        isToolbarVisible = !isFocusModeActive
    }

    /// Signals that the view has consumed `pendingScrollAnchor`.
    public func clearPendingAnchor() {
        pendingScrollAnchor = nil
    }

    // MARK: - Depth / tone labels

    /// The available depth variants filtered to those present in the chapter
    /// and belonging to the known variant family. Unknown cases are hidden.
    public var availableVariants: [VariantKey] {
        variantFamily.variantKeys.filter { chapter.availableVariants.contains($0) }
    }

    /// Human-readable display label for a depth variant.
    public func displayName(for variant: VariantKey) -> String {
        switch variant {
        case .easy:        return "Easy"
        case .medium:      return "Medium"
        case .hard:        return "Hard"
        case .precise:     return "Precise"
        case .balanced:    return "Balanced"
        case .challenging: return "Challenging"
        case .unknown:     return ""
        }
    }

    /// Human-readable display label for a tone.
    public func displayName(for tone: ToneKey) -> String {
        switch tone {
        case .gentle:      return "Gentle"
        case .direct:      return "Direct"
        case .competitive: return "Competitive"
        case .unknown:     return ""
        }
    }

    // MARK: - Private helpers

    private func rebuildContent(preservingTopIndex topIndex: Int) {
        let resolved = resolver.resolve(
            chapter: chapter,
            selectedVariant: selectedVariant,
            selectedTone: selectedTone
        )
        let newBlocks = builder.build(from: resolved)
        resolvedChapter = resolved
        blocks = newBlocks
        pendingScrollAnchor = max(0, min(topIndex, newBlocks.count - 1))
    }

    private func persistPreferences() {
        let prefs = BookReadingPreferences(
            variantKeyRaw: selectedVariant.rawValue,
            toneKeyRaw: selectedTone.rawValue
        )
        try? store.set(prefs, forKey: BookReadingPreferences.storageKey(for: bookId))
    }
}

// MARK: - VariantKey / ToneKey helpers

private extension VariantKey {
    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

private extension ToneKey {
    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}
