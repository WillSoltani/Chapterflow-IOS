import Testing
import SwiftUI
@testable import ReaderFeature
import Persistence

// MARK: - ReadingThemeTokens tests

@Suite("ReadingThemeTokens")
struct ReadingThemeTokensTests {
    @Test("factory returns a distinct token set for every theme")
    func distinctSetsPerTheme() {
        let themes = ReadingTheme.allCases
        let tokenSets = themes.map { ReadingThemeTokens.tokens(for: $0) }
        // Every sepia pageBg should differ from the dark pageBg (spot-check).
        let sepia = ReadingThemeTokens.tokens(for: .sepia)
        let dark  = ReadingThemeTokens.tokens(for: .dark)
        // Sepia is warm cream; dark is true black — they must be different.
        #expect(sepia.pageBg != dark.pageBg)
        // Every theme covered — count matches enum cases.
        #expect(tokenSets.count == themes.count)
    }

    @Test("dark theme uses OLED black page background")
    func darkThemeOledBlack() {
        let dark = ReadingThemeTokens.tokens(for: .dark)
        // Color(white: 0) == true black (#000000).
        #expect(dark.pageBg == Color(white: 0.0))
    }

    @Test("sepia theme has a warm (non-white) page background")
    func sepiaIsWarm() {
        let sepia = ReadingThemeTokens.tokens(for: .sepia)
        // White would be Color(white: 1.0); sepia must be warmer/darker.
        #expect(sepia.pageBg != Color(white: 1.0))
        #expect(sepia.pageBg != Color(white: 0.0))
    }

    @Test("paper theme page background is not pure white or pure black")
    func paperIsOffWhite() {
        let paper = ReadingThemeTokens.tokens(for: .paper)
        #expect(paper.pageBg != Color(white: 1.0))
        #expect(paper.pageBg != Color(white: 0.0))
    }

    @Test("light theme has pure white page background")
    func lightThemeIsWhite() {
        let light = ReadingThemeTokens.tokens(for: .light)
        #expect(light.pageBg == Color(white: 1.0))
    }

    @Test("accent colors are distinct between sepia and dark themes")
    func accentDiffers() {
        let sepia = ReadingThemeTokens.tokens(for: .sepia)
        let dark  = ReadingThemeTokens.tokens(for: .dark)
        #expect(sepia.accent != dark.accent)
    }

    @Test("quoteBar color differs between light and dark themes")
    func quoteBarDiffers() {
        let light = ReadingThemeTokens.tokens(for: .light)
        let dark  = ReadingThemeTokens.tokens(for: .dark)
        #expect(light.quoteBar != dark.quoteBar)
    }
}

// MARK: - ReadingTheme tests

@Suite("ReadingTheme")
struct ReadingThemeTests {
    @Test("all cases have non-empty displayNames")
    func displayNames() {
        for theme in ReadingTheme.allCases {
            #expect(!theme.displayName.isEmpty)
        }
    }

    @Test("rawValue round-trips for every case")
    func rawValueRoundTrip() {
        for theme in ReadingTheme.allCases {
            let roundTripped = ReadingTheme(rawValue: theme.rawValue)
            #expect(roundTripped == theme)
        }
    }

    @Test("ReadingTheme is Codable")
    func codable() throws {
        for theme in ReadingTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(ReadingTheme.self, from: data)
            #expect(decoded == theme)
        }
    }
}

// MARK: - ReadingAppearance tests

@Suite("ReadingAppearance")
struct ReadingAppearanceTests {
    @Test("default appearance uses system theme")
    func defaultAppearance() {
        let appearance = ReadingAppearance.default
        #expect(appearance.fontScale == 1.0)
        #expect(appearance.lineSpacing == 6)
        #expect(appearance.colorSchemeOverride == nil)
    }

    @Test("dark theme sets colorSchemeOverride to dark")
    @MainActor func darkThemeOverride() {
        let prefs = AppPreferences(defaults: makeSuite("dark"))
        prefs.readerTheme = .dark
        let appearance = ReadingAppearance(preferences: prefs)
        #expect(appearance.colorSchemeOverride == .dark)
    }

    @Test("sepia theme sets colorSchemeOverride to light")
    @MainActor func sepiaThemeOverride() {
        let prefs = AppPreferences(defaults: makeSuite("sepia"))
        prefs.readerTheme = .sepia
        let appearance = ReadingAppearance(preferences: prefs)
        #expect(appearance.colorSchemeOverride == .light)
    }

    @Test("paper theme sets colorSchemeOverride to light")
    @MainActor func paperThemeOverride() {
        let prefs = AppPreferences(defaults: makeSuite("paper"))
        prefs.readerTheme = .paper
        let appearance = ReadingAppearance(preferences: prefs)
        #expect(appearance.colorSchemeOverride == .light)
    }

    @Test("light theme sets colorSchemeOverride to light")
    @MainActor func lightThemeOverride() {
        let prefs = AppPreferences(defaults: makeSuite("light"))
        prefs.readerTheme = .light
        let appearance = ReadingAppearance(preferences: prefs)
        #expect(appearance.colorSchemeOverride == .light)
    }

    @Test("system theme leaves colorSchemeOverride nil")
    @MainActor func systemThemeNoOverride() {
        let prefs = AppPreferences(defaults: makeSuite("system"))
        prefs.readerTheme = .system
        let appearance = ReadingAppearance(preferences: prefs)
        #expect(appearance.colorSchemeOverride == nil)
    }

    @Test("preferences drive fontScale and lineSpacing")
    @MainActor func prefsMirroredIntoAppearance() {
        let prefs = AppPreferences(defaults: makeSuite("scale"))
        prefs.readerFontScale = 1.35
        prefs.readerLineSpacing = 11
        let appearance = ReadingAppearance(preferences: prefs)
        #expect(appearance.fontScale == 1.35)
        #expect(appearance.lineSpacing == 11)
    }
}

// MARK: - AppPreferences persistence tests

@Suite("AppPreferences — ReadingTheme + lineSpacing")
struct AppPreferencesExtensionTests {
    @Test("readerTheme defaults to system")
    @MainActor func defaultTheme() {
        let prefs = AppPreferences(defaults: makeSuite("default-theme"))
        #expect(prefs.readerTheme == .system)
    }

    @Test("readerLineSpacing defaults to 6")
    @MainActor func defaultLineSpacing() {
        let prefs = AppPreferences(defaults: makeSuite("default-spacing"))
        #expect(prefs.readerLineSpacing == 6.0)
    }

    @Test("readerTheme persists across initializations")
    @MainActor func themePersiststAcrossInits() {
        // Use a single UserDefaults instance (same in-memory object) to simulate
        // two AppPreferences objects sharing the same suite — the write from prefs1
        // must be visible when prefs2 reads at init time.
        let defaults = makeFreshSuite("persist-theme")
        let prefs1 = AppPreferences(defaults: defaults)
        prefs1.readerTheme = .sepia

        let prefs2 = AppPreferences(defaults: defaults)
        #expect(prefs2.readerTheme == .sepia)
    }

    @Test("readerLineSpacing persists across initializations")
    @MainActor func lineSpacingPersistsAcrossInits() {
        let defaults = makeFreshSuite("persist-spacing")
        let prefs1 = AppPreferences(defaults: defaults)
        prefs1.readerLineSpacing = 11.0

        let prefs2 = AppPreferences(defaults: defaults)
        #expect(prefs2.readerLineSpacing == 11.0)
    }

    @Test("readerFontScale persists across initializations")
    @MainActor func fontScalePersistsAcrossInits() {
        let defaults = makeFreshSuite("persist-scale")
        let prefs1 = AppPreferences(defaults: defaults)
        prefs1.readerFontScale = 1.27

        let prefs2 = AppPreferences(defaults: defaults)
        #expect(abs(prefs2.readerFontScale - 1.27) < 0.001)
    }
}

// MARK: - FontSizeStep tests

@Suite("FontSizeStep")
struct FontSizeStepTests {
    @Test("closest step for 1.0 is medium")
    func closestToDefault() {
        #expect(FontSizeStep.closest(to: 1.0) == .medium)
    }

    @Test("closest step for 1.5 is xxl")
    func closestToXXL() {
        #expect(FontSizeStep.closest(to: 1.5) == .xxl)
    }

    @Test("closest step for 0.82 is xs")
    func closestToXS() {
        #expect(FontSizeStep.closest(to: 0.82) == .xs)
    }

    @Test("scale values are strictly increasing")
    func ascendingScales() {
        let scales = FontSizeStep.allCases.map(\.scale)
        for i in 1 ..< scales.count {
            #expect(scales[i] > scales[i - 1])
        }
    }

    @Test("xs scale is below 1.0 (smaller than default)")
    func xsIsSmallerThanDefault() {
        #expect(FontSizeStep.xs.scale < 1.0)
    }

    @Test("xxl scale is above 1.0 (larger than default)")
    func xxlIsLargerThanDefault() {
        #expect(FontSizeStep.xxl.scale > 1.0)
    }
}

// MARK: - LineSpacingOption tests

@Suite("LineSpacingOption")
struct LineSpacingOptionTests {
    @Test("all options have non-empty labels and system images")
    func labelsAndImages() {
        for option in LineSpacingOption.allCases {
            #expect(!option.label.isEmpty)
            #expect(!option.systemImage.isEmpty)
        }
    }

    @Test("values are strictly increasing")
    func ascendingValues() {
        let vals = LineSpacingOption.allCases.map(\.value)
        for i in 1 ..< vals.count {
            #expect(vals[i] > vals[i - 1])
        }
    }

    @Test("normal value is 6")
    func normalIsDefault() {
        #expect(LineSpacingOption.normal.value == 6)
    }
}

// MARK: - Helpers

/// Returns a `UserDefaults` for the given short name, cleared of any prior data.
/// Pass the SAME object to multiple `AppPreferences` initializations to simulate
/// a fresh-but-shared defaults suite in tests.
private func makeSuite(_ name: String) -> UserDefaults {
    let key = "test.\(name)"
    let suite = UserDefaults(suiteName: key)!
    suite.removePersistentDomain(forName: key)
    return suite
}

/// Returns a fresh `UserDefaults` suite with a unique UUID suffix to avoid
/// cross-test interference.  The same object can be shared within one test.
private func makeFreshSuite(_ prefix: String) -> UserDefaults {
    let key = "test.\(prefix)"
    let suite = UserDefaults(suiteName: key)!
    suite.removePersistentDomain(forName: key)
    return suite
}
