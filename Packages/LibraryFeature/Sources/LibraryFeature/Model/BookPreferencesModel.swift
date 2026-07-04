import Foundation
import Observation
import Models
import Persistence

/// Observable model for per-book reading preferences.
///
/// Owns the user's depth variant, tone, learning mode, and audio preference
/// for a single book. Per-book settings take priority over global `AppPreferences`;
/// when no per-book override exists, the global default is shown as a starting point.
///
/// Persistence layers:
/// - Local: ``KeyValueStore`` via ``BookReadingPreferences`` (immediate, every change).
/// - Server: ``BookPreferencesRepository`` (best-effort, fired on ``syncToServer()``).
@Observable
@MainActor
public final class BookPreferencesModel {

    // MARK: - Identity

    public let bookId: String
    public let variantFamily: VariantFamily

    // MARK: - Selection state

    /// Active depth variant for this book.
    public var selectedVariant: VariantKey {
        didSet { persistLocally() }
    }

    /// Active tone for this book.
    public var selectedTone: ToneKey {
        didSet { persistLocally() }
    }

    /// Preferred learning mode for this book.
    public var learningMode: LearningMode {
        didSet { persistLocally() }
    }

    /// Whether audio narration is the default entry point for this book.
    public var audioNarrationEnabled: Bool {
        didSet { persistLocally() }
    }

    // MARK: - Override state

    /// `true` when a per-book override is stored; `false` when falling back to global defaults.
    public private(set) var hasPerBookOverride: Bool

    // MARK: - Recommended variant (placeholder for P6.4)

    /// The server-recommended depth for this reader.
    /// `nil` hides the hint. Set by the host after loading
    /// `GET /book/me/books/{bookId}/depth-recommendation`.
    public var recommendedVariant: VariantKey?

    // MARK: - Server sync state

    public private(set) var isSyncing: Bool = false
    public private(set) var syncError: String?

    // MARK: - Dependencies

    @ObservationIgnored private let store: KeyValueStore
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let repository: (any BookPreferencesRepository)?
    /// Suppresses `persistLocally()` during a reset to avoid immediately re-writing defaults.
    @ObservationIgnored private var isResetting = false

    // MARK: - Init

    public init(
        bookId: String,
        variantFamily: VariantFamily,
        store: KeyValueStore = KeyValueStore(),
        preferences: AppPreferences,
        repository: (any BookPreferencesRepository)? = nil
    ) {
        self.bookId = bookId
        self.variantFamily = variantFamily
        self.store = store
        self.preferences = preferences
        self.repository = repository

        let saved = store.value(
            BookReadingPreferences.self,
            forKey: BookReadingPreferences.storageKey(for: bookId)
        )
        if let saved {
            self.selectedVariant = VariantKey(rawValue: saved.variantKeyRaw)
            self.selectedTone = ToneKey(rawValue: saved.toneKeyRaw)
            self.learningMode = LearningMode(rawValue: saved.learningMode) ?? .reading
            self.audioNarrationEnabled = saved.audioNarrationEnabled
            self.hasPerBookOverride = true
        } else {
            self.selectedVariant = VariantKey(rawValue: preferences.depthVariant.rawValue)
            self.selectedTone = ToneKey(rawValue: preferences.readingTone.rawValue)
            self.learningMode = .reading
            self.audioNarrationEnabled = false
            self.hasPerBookOverride = false
        }
    }

    // MARK: - Derived

    /// The depth variants available for this book's family, excluding `.unknown`.
    public var availableVariants: [VariantKey] {
        variantFamily.variantKeys
    }

    // MARK: - Actions

    /// Fires a best-effort server sync for `preferredVariant`.
    /// Call on sheet dismiss after all selections are made.
    public func syncToServer() {
        guard let repository else { return }
        isSyncing = true
        syncError = nil
        let bId = bookId
        let variantKey = selectedVariant.rawValue
        let repo = repository
        Task { [weak self] in
            defer { Task { @MainActor in self?.isSyncing = false } }
            do {
                try await repo.patchBookPreferredVariant(bookId: bId, variantKey: variantKey)
            } catch {
                await MainActor.run { self?.syncError = error.localizedDescription }
            }
        }
    }

    /// Removes the per-book override and resets to global `AppPreferences` defaults.
    public func resetToGlobalDefaults() {
        isResetting = true
        defer { isResetting = false }
        store.removeValue(forKey: BookReadingPreferences.storageKey(for: bookId))
        hasPerBookOverride = false
        selectedVariant = VariantKey(rawValue: preferences.depthVariant.rawValue)
        selectedTone = ToneKey(rawValue: preferences.readingTone.rawValue)
        learningMode = .reading
        audioNarrationEnabled = false
    }

    // MARK: - Display helpers

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

    public func description(for variant: VariantKey) -> String {
        switch variant {
        case .easy:        return "Simplified explanations, core concepts only"
        case .medium:      return "Balanced depth and practical context"
        case .hard:        return "Full nuance, edge cases, deep examples"
        case .precise:     return "Rigorous definitions and technical accuracy"
        case .balanced:    return "Conceptual clarity with real-world grounding"
        case .challenging: return "Expert-level framing and advanced applications"
        case .unknown:     return ""
        }
    }

    public func displayName(for tone: ToneKey) -> String {
        switch tone {
        case .gentle:      return "Gentle"
        case .direct:      return "Direct"
        case .competitive: return "Competitive"
        case .unknown:     return ""
        }
    }

    public func description(for tone: ToneKey) -> String {
        switch tone {
        case .gentle:      return "Encouraging and supportive"
        case .direct:      return "Efficient and no-nonsense"
        case .competitive: return "High-performance and challenging"
        case .unknown:     return ""
        }
    }

    // MARK: - Private

    private func persistLocally() {
        guard !isResetting else { return }
        let prefs = BookReadingPreferences(
            variantKeyRaw: selectedVariant.rawValue,
            toneKeyRaw: selectedTone.rawValue,
            learningMode: learningMode.rawValue,
            audioNarrationEnabled: audioNarrationEnabled
        )
        try? store.set(prefs, forKey: BookReadingPreferences.storageKey(for: bookId))
        hasPerBookOverride = true
    }
}
