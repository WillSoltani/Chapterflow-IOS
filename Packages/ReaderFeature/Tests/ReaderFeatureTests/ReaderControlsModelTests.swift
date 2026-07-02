import Testing
import Foundation
@testable import ReaderFeature
import Models
import Persistence

// MARK: - Helpers

private func makeChapter() throws -> Chapter {
    let json = """
    {
        "chapterId": "test-ch-1",
        "number": 1,
        "title": "Test Chapter",
        "readingTimeMinutes": 5,
        "activeVariant": "medium",
        "availableVariants": ["easy", "medium", "hard"],
        "content": {
            "chapterBreakdown": {
                "gentle": "Gentle medium.", "direct": "Direct medium.", "competitive": "Competitive medium."
            }
        },
        "contentVariants": {
            "easy": {
                "chapterBreakdown": {
                    "gentle": "Gentle easy.", "direct": "Direct easy.", "competitive": "Competitive easy."
                }
            },
            "medium": {
                "chapterBreakdown": {
                    "gentle": "Gentle medium.", "direct": "Direct medium.", "competitive": "Competitive medium."
                }
            },
            "hard": {
                "chapterBreakdown": {
                    "gentle": "Gentle hard.", "direct": "Direct hard.", "competitive": "Competitive hard."
                },
                "keyTakeaways": [
                    {
                        "point": {
                            "gentle": "Hard gentle KT.", "direct": "Hard direct KT.", "competitive": "Hard competitive KT."
                        },
                        "moreDetails": null
                    }
                ]
            }
        },
        "examples": []
    }
    """
    return try JSONDecoder.chapterFlow.decode(Chapter.self, from: Data(json.utf8))
}

@MainActor
private func makeStore(_ name: String) -> KeyValueStore {
    let key = "test.readercontrols.\(name)"
    let defaults = UserDefaults(suiteName: key)!
    defaults.removePersistentDomain(forName: key)
    return KeyValueStore(defaults: defaults)
}

@MainActor
private func makePrefs(_ name: String = "default") -> AppPreferences {
    let key = "test.readerprefs.\(name)"
    let defaults = UserDefaults(suiteName: key)!
    defaults.removePersistentDomain(forName: key)
    return AppPreferences(defaults: defaults)
}

// MARK: - ReaderControlsModel tests

@Suite("ReaderControlsModel")
struct ReaderControlsModelTests {

    // MARK: - Initial state

    @Test("defaults to variantFamily default when no saved prefs")
    @MainActor func defaultsToFamilyDefault() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-1",
            variantFamily: .emh,
            preferences: makePrefs("default-variant"),
            store: makeStore("default-variant")
        )
        #expect(model.selectedVariant == .medium)
    }

    @Test("defaults to global preference tone when no saved prefs")
    @MainActor func defaultsToGlobalTone() throws {
        let chapter = try makeChapter()
        let prefs = makePrefs("default-tone")
        prefs.readingTone = .direct
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-2",
            variantFamily: .emh,
            preferences: prefs,
            store: makeStore("default-tone")
        )
        #expect(model.selectedTone == .direct)
    }

    @Test("restores saved per-book variant from store")
    @MainActor func restoresSavedVariant() throws {
        let chapter = try makeChapter()
        let store = makeStore("restore-variant")
        // Pre-save "hard" for this book.
        let savedPrefs = BookReadingPreferences(variantKeyRaw: "hard", toneKeyRaw: "gentle")
        try store.set(savedPrefs, forKey: BookReadingPreferences.storageKey(for: "book-3"))
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-3",
            variantFamily: .emh,
            preferences: makePrefs("restore-variant"),
            store: store
        )
        #expect(model.selectedVariant == .hard)
    }

    @Test("restores saved per-book tone from store")
    @MainActor func restoresSavedTone() throws {
        let chapter = try makeChapter()
        let store = makeStore("restore-tone")
        let savedPrefs = BookReadingPreferences(variantKeyRaw: "medium", toneKeyRaw: "competitive")
        try store.set(savedPrefs, forKey: BookReadingPreferences.storageKey(for: "book-4"))
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-4",
            variantFamily: .emh,
            preferences: makePrefs("restore-tone"),
            store: store
        )
        #expect(model.selectedTone == .competitive)
    }

    @Test("initial blocks are non-empty")
    @MainActor func initialBlocksNonEmpty() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-5",
            variantFamily: .emh,
            preferences: makePrefs("initial-blocks"),
            store: makeStore("initial-blocks")
        )
        #expect(!model.blocks.isEmpty)
    }

    // MARK: - switchVariant

    @Test("switchVariant updates selectedVariant")
    @MainActor func switchVariantUpdatesSelection() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-sv-1",
            variantFamily: .emh,
            preferences: makePrefs("sv-1"),
            store: makeStore("sv-1")
        )
        model.switchVariant(.hard, currentTopIndex: 0)
        #expect(model.selectedVariant == .hard)
    }

    @Test("switchVariant rebuilds blocks")
    @MainActor func switchVariantRebuildsBlocks() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-sv-2",
            variantFamily: .emh,
            preferences: makePrefs("sv-2"),
            store: makeStore("sv-2")
        )
        let initialCount = model.blocks.count
        model.switchVariant(.hard, currentTopIndex: 0)
        // Hard has an extra key takeaway, so block count should increase.
        #expect(model.blocks.count > initialCount)
    }

    @Test("switchVariant sets pendingScrollAnchor")
    @MainActor func switchVariantSetsPendingAnchor() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-sv-3",
            variantFamily: .emh,
            preferences: makePrefs("sv-3"),
            store: makeStore("sv-3")
        )
        model.switchVariant(.easy, currentTopIndex: 2)
        #expect(model.pendingScrollAnchor != nil)
    }

    @Test("switchVariant clamps pendingScrollAnchor to new block count")
    @MainActor func switchVariantClampsAnchor() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-sv-4",
            variantFamily: .emh,
            preferences: makePrefs("sv-4"),
            store: makeStore("sv-4")
        )
        model.switchVariant(.easy, currentTopIndex: 9999)
        let anchor = try #require(model.pendingScrollAnchor)
        #expect(anchor < model.blocks.count)
        #expect(anchor >= 0)
    }

    @Test("switchVariant is a no-op when variant is already selected")
    @MainActor func switchVariantNoOpIfSame() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-sv-5",
            variantFamily: .emh,
            preferences: makePrefs("sv-5"),
            store: makeStore("sv-5")
        )
        let before = model.blocks.count
        model.switchVariant(.medium, currentTopIndex: 0)
        #expect(model.blocks.count == before)
        #expect(model.pendingScrollAnchor == nil)
    }

    @Test("switchVariant ignores unknown variant")
    @MainActor func switchVariantIgnoresUnknown() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-sv-6",
            variantFamily: .emh,
            preferences: makePrefs("sv-6"),
            store: makeStore("sv-6")
        )
        model.switchVariant(.unknown("future-variant"), currentTopIndex: 0)
        #expect(model.selectedVariant == .medium)
    }

    // MARK: - switchTone

    @Test("switchTone updates selectedTone")
    @MainActor func switchToneUpdatesSelection() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-st-1",
            variantFamily: .emh,
            preferences: makePrefs("st-1"),
            store: makeStore("st-1")
        )
        model.switchTone(.competitive, currentTopIndex: 0)
        #expect(model.selectedTone == .competitive)
    }

    @Test("switchTone is a no-op when tone is already selected")
    @MainActor func switchToneNoOpIfSame() throws {
        let chapter = try makeChapter()
        let prefs = makePrefs("st-2")
        prefs.readingTone = .gentle
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-st-2",
            variantFamily: .emh,
            preferences: prefs,
            store: makeStore("st-2")
        )
        model.switchTone(.gentle, currentTopIndex: 0)
        #expect(model.pendingScrollAnchor == nil)
    }

    @Test("switchTone ignores unknown tone")
    @MainActor func switchToneIgnoresUnknown() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-st-3",
            variantFamily: .emh,
            preferences: makePrefs("st-3"),
            store: makeStore("st-3")
        )
        let toneBefore = model.selectedTone
        model.switchTone(.unknown("future-tone"), currentTopIndex: 0)
        #expect(model.selectedTone == toneBefore)
    }

    // MARK: - Persistence

    @Test("switchVariant persists to store")
    @MainActor func switchVariantPersists() throws {
        let chapter = try makeChapter()
        let store = makeStore("persist-variant")
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-p-1",
            variantFamily: .emh,
            preferences: makePrefs("persist-variant"),
            store: store
        )
        model.switchVariant(.easy, currentTopIndex: 0)
        let saved = store.value(
            BookReadingPreferences.self,
            forKey: BookReadingPreferences.storageKey(for: "book-p-1")
        )
        #expect(saved?.variantKeyRaw == "easy")
    }

    @Test("switchTone persists to store")
    @MainActor func switchTonePersists() throws {
        let chapter = try makeChapter()
        let store = makeStore("persist-tone")
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-p-2",
            variantFamily: .emh,
            preferences: makePrefs("persist-tone"),
            store: store
        )
        // Default is .direct; switch to .gentle so it's a real change.
        model.switchTone(.gentle, currentTopIndex: 0)
        let saved = store.value(
            BookReadingPreferences.self,
            forKey: BookReadingPreferences.storageKey(for: "book-p-2")
        )
        #expect(saved?.toneKeyRaw == "gentle")
    }

    // MARK: - UI state

    @Test("toggleFocusMode hides toolbar")
    @MainActor func focusModeHidesToolbar() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-fm-1",
            variantFamily: .emh,
            preferences: makePrefs("fm-1"),
            store: makeStore("fm-1")
        )
        model.toggleFocusMode()
        #expect(model.isFocusModeActive)
        #expect(!model.isToolbarVisible)
    }

    @Test("toggleFocusMode restores toolbar on exit")
    @MainActor func focusModeRestoresToolbar() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-fm-2",
            variantFamily: .emh,
            preferences: makePrefs("fm-2"),
            store: makeStore("fm-2")
        )
        model.toggleFocusMode()
        model.toggleFocusMode()
        #expect(!model.isFocusModeActive)
        #expect(model.isToolbarVisible)
    }

    @Test("clearPendingAnchor resets pendingScrollAnchor")
    @MainActor func clearPendingAnchor() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-anchor",
            variantFamily: .emh,
            preferences: makePrefs("anchor"),
            store: makeStore("anchor")
        )
        model.switchVariant(.easy, currentTopIndex: 1)
        #expect(model.pendingScrollAnchor != nil)
        model.clearPendingAnchor()
        #expect(model.pendingScrollAnchor == nil)
    }

    // MARK: - Available variants & labels

    @Test("availableVariants returns EMH keys present in chapter")
    @MainActor func availableVariantsEMH() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-av-1",
            variantFamily: .emh,
            preferences: makePrefs("av-1"),
            store: makeStore("av-1")
        )
        #expect(model.availableVariants == [.easy, .medium, .hard])
    }

    @Test("displayName returns correct label for each variant")
    @MainActor func displayNamesVariants() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-dn-1",
            variantFamily: .emh,
            preferences: makePrefs("dn-1"),
            store: makeStore("dn-1")
        )
        #expect(model.displayName(for: .easy) == "Easy")
        #expect(model.displayName(for: .medium) == "Medium")
        #expect(model.displayName(for: .hard) == "Hard")
        #expect(model.displayName(for: .precise) == "Precise")
        #expect(model.displayName(for: .balanced) == "Balanced")
        #expect(model.displayName(for: .challenging) == "Challenging")
        #expect(model.displayName(for: VariantKey.unknown("x")) == "")
    }

    @Test("displayName returns correct label for each tone")
    @MainActor func displayNamesTones() throws {
        let chapter = try makeChapter()
        let model = ReaderControlsModel(
            chapter: chapter,
            bookId: "book-dn-2",
            variantFamily: .emh,
            preferences: makePrefs("dn-2"),
            store: makeStore("dn-2")
        )
        #expect(model.displayName(for: .gentle) == "Gentle")
        #expect(model.displayName(for: .direct) == "Direct")
        #expect(model.displayName(for: .competitive) == "Competitive")
        #expect(model.displayName(for: ToneKey.unknown("x")) == "")
    }
}

// MARK: - BookReadingPreferences tests

@Suite("BookReadingPreferences")
struct BookReadingPreferencesTests {

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let prefs = BookReadingPreferences(variantKeyRaw: "hard", toneKeyRaw: "competitive")
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(BookReadingPreferences.self, from: data)
        #expect(decoded.variantKeyRaw == "hard")
        #expect(decoded.toneKeyRaw == "competitive")
    }

    @Test("storageKey is stable for the same bookId")
    func storageKeyStable() {
        let key1 = BookReadingPreferences.storageKey(for: "book-abc")
        let key2 = BookReadingPreferences.storageKey(for: "book-abc")
        #expect(key1 == key2)
    }

    @Test("storageKey differs for different bookIds")
    func storageKeyDiffers() {
        let key1 = BookReadingPreferences.storageKey(for: "book-abc")
        let key2 = BookReadingPreferences.storageKey(for: "book-xyz")
        #expect(key1 != key2)
    }

    @Test("KeyValueStore round-trip persists and restores prefs")
    @MainActor func keyValueStoreRoundTrip() throws {
        let suiteName = "test.bookreadingprefs.roundtrip"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = KeyValueStore(defaults: defaults)

        let prefs = BookReadingPreferences(variantKeyRaw: "balanced", toneKeyRaw: "direct")
        let key = BookReadingPreferences.storageKey(for: "my-book")
        try store.set(prefs, forKey: key)

        let restored = store.value(BookReadingPreferences.self, forKey: key)
        #expect(restored?.variantKeyRaw == "balanced")
        #expect(restored?.toneKeyRaw == "direct")
    }
}

// MARK: - ReadingMode tests

@Suite("ReadingMode")
struct ReadingModeTests {

    @Test("all cases have stable rawValues")
    func rawValues() {
        #expect(ReadingMode.scroll.rawValue == "scroll")
        #expect(ReadingMode.paginate.rawValue == "paginate")
    }

    @Test("CaseIterable covers both modes")
    func allCases() {
        #expect(ReadingMode.allCases.count == 2)
    }
}
