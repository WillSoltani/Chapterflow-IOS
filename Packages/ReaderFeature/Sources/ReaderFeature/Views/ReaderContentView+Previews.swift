#if DEBUG
import SwiftUI
import Persistence

// MARK: - Helpers

@MainActor
private func prefs(
    theme: ReadingTheme = .system,
    fontScale: Double = 1.0,
    lineSpacing: Double = 6
) -> AppPreferences {
    let p = AppPreferences(defaults: UserDefaults(suiteName: "reader.preview.\(theme.rawValue)"))
    p.readerTheme = theme
    p.readerFontScale = fontScale
    p.readerLineSpacing = lineSpacing
    return p
}

// MARK: - Previews

#Preview("System — Light") {
    ReaderContentView(chapter: previewChapterEMH, preferences: prefs())
}

#Preview("Light theme") {
    ReaderContentView(chapter: previewChapterEMH, preferences: prefs(theme: .light))
}

#Preview("Sepia theme") {
    ReaderContentView(chapter: previewChapterEMH, preferences: prefs(theme: .sepia))
}

#Preview("Dark theme — OLED") {
    ReaderContentView(chapter: previewChapterEMH, preferences: prefs(theme: .dark))
}

#Preview("Paper theme") {
    ReaderContentView(chapter: previewChapterPBC, preferences: prefs(theme: .paper))
}

#Preview("Large font (1.5×) — Sepia") {
    ReaderContentView(
        chapter: previewChapterEMH,
        preferences: prefs(theme: .sepia, fontScale: 1.5, lineSpacing: 11)
    )
}

#Preview("Accessibility XXL — System") {
    ReaderContentView(chapter: previewChapterEMH, preferences: prefs())
        .dynamicTypeSize(.accessibility3)
}

#Preview("Accessibility XXL — Sepia") {
    ReaderContentView(chapter: previewChapterPBC, preferences: prefs(theme: .sepia))
        .dynamicTypeSize(.accessibility3)
}
#endif
