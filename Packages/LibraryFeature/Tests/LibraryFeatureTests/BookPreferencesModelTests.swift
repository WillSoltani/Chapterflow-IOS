import Testing
import Foundation
@testable import LibraryFeature
import Models
import Persistence

// MARK: - Helpers

@MainActor
private func makeStore(_ name: String) -> KeyValueStore {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return KeyValueStore(defaults: defaults)
}

@MainActor
private func makePrefs(_ name: String, tone: ReadingTone = .direct, depth: DepthVariant = .medium) -> AppPreferences {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    let prefs = AppPreferences(defaults: defaults)
    prefs.readingTone = tone
    prefs.depthVariant = depth
    return prefs
}

// MARK: - BookPreferencesModel tests

@Suite("BookPreferencesModel")
@MainActor
struct BookPreferencesModelTests {

    // MARK: - Initial state from global prefs (no override)

    @Test("defaults to global depthVariant when no per-book override")
    func defaultsToGlobalDepth() {
        let prefs = makePrefs("bpm.nooverride.depth", depth: .hard)
        let model = BookPreferencesModel(
            bookId: "book-1",
            variantFamily: .emh,
            store: makeStore("bpm.nooverride.depth.store"),
            preferences: prefs
        )
        #expect(model.selectedVariant == .hard)
        #expect(!model.hasPerBookOverride)
    }

    @Test("defaults to global readingTone when no per-book override")
    func defaultsToGlobalTone() {
        let prefs = makePrefs("bpm.nooverride.tone", tone: .gentle)
        let model = BookPreferencesModel(
            bookId: "book-2",
            variantFamily: .emh,
            store: makeStore("bpm.nooverride.tone.store"),
            preferences: prefs
        )
        #expect(model.selectedTone == .gentle)
        #expect(!model.hasPerBookOverride)
    }

    @Test("defaults learningMode to .reading when no override")
    func defaultsLearningModeToReading() {
        let model = BookPreferencesModel(
            bookId: "book-3",
            variantFamily: .emh,
            store: makeStore("bpm.default.mode"),
            preferences: makePrefs("bpm.default.mode.prefs")
        )
        #expect(model.learningMode == .reading)
    }

    @Test("defaults audioNarrationEnabled to false when no override")
    func defaultsAudioNarrationToFalse() {
        let model = BookPreferencesModel(
            bookId: "book-4",
            variantFamily: .emh,
            store: makeStore("bpm.default.audio"),
            preferences: makePrefs("bpm.default.audio.prefs")
        )
        #expect(!model.audioNarrationEnabled)
    }

    // MARK: - Restores from per-book override

    @Test("restores saved per-book variant from store")
    func restoresSavedVariant() throws {
        let store = makeStore("bpm.restore.variant")
        let saved = BookReadingPreferences(variantKeyRaw: "easy", toneKeyRaw: "gentle")
        try store.set(saved, forKey: BookReadingPreferences.storageKey(for: "book-5"))
        let model = BookPreferencesModel(
            bookId: "book-5",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.restore.variant.prefs")
        )
        #expect(model.selectedVariant == .easy)
        #expect(model.hasPerBookOverride)
    }

    @Test("restores saved per-book tone from store")
    func restoresSavedTone() throws {
        let store = makeStore("bpm.restore.tone")
        let saved = BookReadingPreferences(variantKeyRaw: "medium", toneKeyRaw: "competitive")
        try store.set(saved, forKey: BookReadingPreferences.storageKey(for: "book-6"))
        let model = BookPreferencesModel(
            bookId: "book-6",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.restore.tone.prefs")
        )
        #expect(model.selectedTone == .competitive)
    }

    @Test("restores saved learningMode from store")
    func restoresSavedLearningMode() throws {
        let store = makeStore("bpm.restore.mode")
        let saved = BookReadingPreferences(
            variantKeyRaw: "medium",
            toneKeyRaw: "direct",
            learningMode: "listening",
            audioNarrationEnabled: false
        )
        try store.set(saved, forKey: BookReadingPreferences.storageKey(for: "book-7"))
        let model = BookPreferencesModel(
            bookId: "book-7",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.restore.mode.prefs")
        )
        #expect(model.learningMode == .listening)
    }

    @Test("restores saved audioNarrationEnabled from store")
    func restoresSavedAudio() throws {
        let store = makeStore("bpm.restore.audio")
        let saved = BookReadingPreferences(
            variantKeyRaw: "medium",
            toneKeyRaw: "direct",
            learningMode: "reading",
            audioNarrationEnabled: true
        )
        try store.set(saved, forKey: BookReadingPreferences.storageKey(for: "book-8"))
        let model = BookPreferencesModel(
            bookId: "book-8",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.restore.audio.prefs")
        )
        #expect(model.audioNarrationEnabled)
    }

    // MARK: - Local persistence on change

    @Test("changing selectedVariant immediately writes to store and sets hasPerBookOverride")
    func variantChangePersists() throws {
        let store = makeStore("bpm.persist.variant")
        let model = BookPreferencesModel(
            bookId: "book-9",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.persist.variant.prefs")
        )
        model.selectedVariant = .hard
        let saved = store.value(BookReadingPreferences.self, forKey: BookReadingPreferences.storageKey(for: "book-9"))
        #expect(saved?.variantKeyRaw == "hard")
        #expect(model.hasPerBookOverride)
    }

    @Test("changing selectedTone immediately writes to store")
    func toneChangePersists() throws {
        let store = makeStore("bpm.persist.tone")
        let model = BookPreferencesModel(
            bookId: "book-10",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.persist.tone.prefs")
        )
        model.selectedTone = .gentle
        let saved = store.value(BookReadingPreferences.self, forKey: BookReadingPreferences.storageKey(for: "book-10"))
        #expect(saved?.toneKeyRaw == "gentle")
    }

    @Test("changing learningMode immediately writes to store")
    func learningModeChangePersists() throws {
        let store = makeStore("bpm.persist.mode")
        let model = BookPreferencesModel(
            bookId: "book-11",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.persist.mode.prefs")
        )
        model.learningMode = .reviewing
        let saved = store.value(BookReadingPreferences.self, forKey: BookReadingPreferences.storageKey(for: "book-11"))
        #expect(saved?.learningMode == "reviewing")
    }

    @Test("changing audioNarrationEnabled immediately writes to store")
    func audioChangePersists() throws {
        let store = makeStore("bpm.persist.audio")
        let model = BookPreferencesModel(
            bookId: "book-12",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.persist.audio.prefs")
        )
        model.audioNarrationEnabled = true
        let saved = store.value(BookReadingPreferences.self, forKey: BookReadingPreferences.storageKey(for: "book-12"))
        #expect(saved?.audioNarrationEnabled == true)
    }

    // MARK: - Reset to global defaults

    @Test("resetToGlobalDefaults clears per-book store and hasPerBookOverride")
    func resetClearsOverride() throws {
        let store = makeStore("bpm.reset")
        let prefs = makePrefs("bpm.reset.prefs", tone: .gentle, depth: .easy)
        // Pre-set an override
        let saved = BookReadingPreferences(variantKeyRaw: "hard", toneKeyRaw: "competitive")
        try store.set(saved, forKey: BookReadingPreferences.storageKey(for: "book-reset"))
        let model = BookPreferencesModel(
            bookId: "book-reset",
            variantFamily: .emh,
            store: store,
            preferences: prefs
        )
        #expect(model.hasPerBookOverride)
        model.resetToGlobalDefaults()
        #expect(!model.hasPerBookOverride)
        let afterReset = store.value(BookReadingPreferences.self, forKey: BookReadingPreferences.storageKey(for: "book-reset"))
        #expect(afterReset == nil)
    }

    @Test("resetToGlobalDefaults restores global variant")
    func resetRestoresGlobalVariant() throws {
        let store = makeStore("bpm.reset.variant")
        let prefs = makePrefs("bpm.reset.variant.prefs", depth: .easy)
        let saved = BookReadingPreferences(variantKeyRaw: "hard", toneKeyRaw: "competitive")
        try store.set(saved, forKey: BookReadingPreferences.storageKey(for: "book-reset2"))
        let model = BookPreferencesModel(
            bookId: "book-reset2",
            variantFamily: .emh,
            store: store,
            preferences: prefs
        )
        model.resetToGlobalDefaults()
        #expect(model.selectedVariant == .easy)
    }

    @Test("resetToGlobalDefaults restores global tone")
    func resetRestoresGlobalTone() throws {
        let store = makeStore("bpm.reset.tone")
        let prefs = makePrefs("bpm.reset.tone.prefs", tone: .gentle)
        let saved = BookReadingPreferences(variantKeyRaw: "hard", toneKeyRaw: "competitive")
        try store.set(saved, forKey: BookReadingPreferences.storageKey(for: "book-reset3"))
        let model = BookPreferencesModel(
            bookId: "book-reset3",
            variantFamily: .emh,
            store: store,
            preferences: prefs
        )
        model.resetToGlobalDefaults()
        #expect(model.selectedTone == .gentle)
    }

    @Test("resetToGlobalDefaults resets learningMode to .reading")
    func resetRestoresLearningMode() throws {
        let store = makeStore("bpm.reset.mode")
        let saved = BookReadingPreferences(
            variantKeyRaw: "medium",
            toneKeyRaw: "direct",
            learningMode: "listening"
        )
        try store.set(saved, forKey: BookReadingPreferences.storageKey(for: "book-reset4"))
        let model = BookPreferencesModel(
            bookId: "book-reset4",
            variantFamily: .emh,
            store: store,
            preferences: makePrefs("bpm.reset.mode.prefs")
        )
        model.resetToGlobalDefaults()
        #expect(model.learningMode == .reading)
    }

    // MARK: - availableVariants

    @Test("availableVariants returns EMH keys for .emh family")
    func availableVariantsEMH() {
        let model = BookPreferencesModel(
            bookId: "book-av-emh",
            variantFamily: .emh,
            store: makeStore("bpm.av.emh"),
            preferences: makePrefs("bpm.av.emh.prefs")
        )
        #expect(model.availableVariants == [.easy, .medium, .hard])
    }

    @Test("availableVariants returns PBC keys for .pbc family")
    func availableVariantsPBC() {
        let model = BookPreferencesModel(
            bookId: "book-av-pbc",
            variantFamily: .pbc,
            store: makeStore("bpm.av.pbc"),
            preferences: makePrefs("bpm.av.pbc.prefs")
        )
        #expect(model.availableVariants == [.precise, .balanced, .challenging])
    }

    @Test("availableVariants returns empty for unknown family")
    func availableVariantsUnknown() {
        let model = BookPreferencesModel(
            bookId: "book-av-unknown",
            variantFamily: .unknown("future"),
            store: makeStore("bpm.av.unknown"),
            preferences: makePrefs("bpm.av.unknown.prefs")
        )
        #expect(model.availableVariants.isEmpty)
    }

    // MARK: - Server sync (FakeBookPreferencesRepository)

    @Test("syncToServer calls patchBookPreferredVariant with correct variantKey")
    func syncToServerCallsRepository() async throws {
        let repo = FakeBookPreferencesRepository()
        let model = BookPreferencesModel(
            bookId: "book-sync",
            variantFamily: .emh,
            store: makeStore("bpm.sync"),
            preferences: makePrefs("bpm.sync.prefs"),
            repository: repo
        )
        model.selectedVariant = .hard
        model.syncToServer()
        // Allow the Task to complete.
        try await Task.sleep(for: .milliseconds(50))
        let lastPatched = await repo.lastPatchedVariantKey
        #expect(lastPatched == "hard")
    }

    @Test("syncToServer is a no-op when no repository is injected")
    func syncToServerNoOpWithoutRepo() {
        let model = BookPreferencesModel(
            bookId: "book-norepo",
            variantFamily: .emh,
            store: makeStore("bpm.norepo"),
            preferences: makePrefs("bpm.norepo.prefs"),
            repository: nil
        )
        model.syncToServer()
        #expect(!model.isSyncing)
    }

    // MARK: - Display helpers

    @Test("displayName returns correct string for each VariantKey")
    func displayNamesVariants() {
        let model = BookPreferencesModel(
            bookId: "book-dn",
            variantFamily: .emh,
            store: makeStore("bpm.dn.store"),
            preferences: makePrefs("bpm.dn.prefs")
        )
        #expect(model.displayName(for: .easy) == "Easy")
        #expect(model.displayName(for: .medium) == "Medium")
        #expect(model.displayName(for: .hard) == "Hard")
        #expect(model.displayName(for: .precise) == "Precise")
        #expect(model.displayName(for: .balanced) == "Balanced")
        #expect(model.displayName(for: .challenging) == "Challenging")
        #expect(model.displayName(for: VariantKey.unknown("x")) == "")
    }

    @Test("displayName returns correct string for each ToneKey")
    func displayNamesTones() {
        let model = BookPreferencesModel(
            bookId: "book-dn-tone",
            variantFamily: .emh,
            store: makeStore("bpm.dn.tone.store"),
            preferences: makePrefs("bpm.dn.tone.prefs")
        )
        #expect(model.displayName(for: .gentle) == "Gentle")
        #expect(model.displayName(for: .direct) == "Direct")
        #expect(model.displayName(for: .competitive) == "Competitive")
        #expect(model.displayName(for: ToneKey.unknown("x")) == "")
    }
}

// MARK: - BookReadingPreferences extended Codable tests

@Suite("BookReadingPreferences extended Codable")
struct BookReadingPreferencesExtendedTests {

    @Test("v1 stored JSON (without learningMode/audioNarrationEnabled) decodes with defaults")
    func v1JSONDecodesWithDefaults() throws {
        let v1Json = """
        {"variantKeyRaw":"hard","toneKeyRaw":"competitive"}
        """
        let decoded = try JSONDecoder().decode(BookReadingPreferences.self, from: Data(v1Json.utf8))
        #expect(decoded.variantKeyRaw == "hard")
        #expect(decoded.toneKeyRaw == "competitive")
        #expect(decoded.learningMode == "reading")
        #expect(!decoded.audioNarrationEnabled)
    }

    @Test("full v2 stored JSON round-trips correctly")
    func v2JSONRoundTrip() throws {
        let prefs = BookReadingPreferences(
            variantKeyRaw: "balanced",
            toneKeyRaw: "gentle",
            learningMode: "listening",
            audioNarrationEnabled: true
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(BookReadingPreferences.self, from: data)
        #expect(decoded.variantKeyRaw == "balanced")
        #expect(decoded.toneKeyRaw == "gentle")
        #expect(decoded.learningMode == "listening")
        #expect(decoded.audioNarrationEnabled)
    }
}

// MARK: - LearningMode tests

@Suite("LearningMode")
struct LearningModeTests {

    @Test("all cases have stable rawValues")
    func stableRawValues() {
        #expect(LearningMode.reading.rawValue == "reading")
        #expect(LearningMode.listening.rawValue == "listening")
        #expect(LearningMode.reviewing.rawValue == "reviewing")
    }

    @Test("displayName returns non-empty string for each case")
    func displayNames() {
        for mode in LearningMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }

    @Test("systemImage returns non-empty string for each case")
    func systemImages() {
        for mode in LearningMode.allCases {
            #expect(!mode.systemImage.isEmpty)
        }
    }

    @Test("Codable round-trip preserves all cases")
    func codableRoundTrip() throws {
        for mode in LearningMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(LearningMode.self, from: data)
            #expect(decoded == mode)
        }
    }
}
