#if DEBUG
import SwiftUI
import Models
import Persistence

// MARK: - Preview helpers

@MainActor
private func makePrefs(
    theme: ReadingTheme = .system,
    fontScale: Double = 1.0,
    lineSpacing: Double = 6.0,
    tone: ReadingTone = .gentle,
    depth: DepthVariant = .medium
) -> AppPreferences {
    let suite = "preview.controls.\(theme.rawValue).\(tone.rawValue).\(depth.rawValue)"
    let defaults = UserDefaults(suiteName: suite)
    defaults?.removePersistentDomain(forName: suite)
    let prefs = AppPreferences(defaults: defaults)
    prefs.readerTheme = theme
    prefs.readerFontScale = fontScale
    prefs.readerLineSpacing = lineSpacing
    prefs.readingTone = tone
    prefs.depthVariant = depth
    return prefs
}

private func makeStore(_ name: String) -> KeyValueStore {
    let suite = "preview.controlsstore.\(name)"
    let defaults = UserDefaults(suiteName: suite)
    defaults?.removePersistentDomain(forName: suite)
    return KeyValueStore(defaults: defaults)
}

// MARK: - Full surface previews

#Preview("Controls — System Light, EMH") {
    ReaderControlSurface(
        chapter: previewChapterRaw,
        bookId: "preview-emh",
        variantFamily: .emh,
        preferences: makePrefs(),
        store: makeStore("emh-light")
    )
    .ignoresSafeArea()
}

#Preview("Controls — Sepia, Direct Tone") {
    ReaderControlSurface(
        chapter: previewChapterRaw,
        bookId: "preview-sepia",
        variantFamily: .emh,
        preferences: makePrefs(theme: .sepia, tone: .direct),
        store: makeStore("emh-sepia")
    )
    .ignoresSafeArea()
}

#Preview("Controls — Dark, Hard, Competitive") {
    ReaderControlSurface(
        chapter: previewChapterRaw,
        bookId: "preview-dark",
        variantFamily: .emh,
        preferences: makePrefs(theme: .dark, tone: .competitive, depth: .hard),
        store: makeStore("emh-dark")
    )
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}

#Preview("Controls — Paper, Accessibility XXL") {
    ReaderControlSurface(
        chapter: previewChapterRaw,
        bookId: "preview-xxl",
        variantFamily: .emh,
        preferences: makePrefs(theme: .paper, fontScale: 1.5, lineSpacing: 11.0),
        store: makeStore("emh-xxl")
    )
    .ignoresSafeArea()
    .dynamicTypeSize(.accessibility3)
}

// MARK: - Toolbar-only previews

#Preview("Toolbar Only — EMH, Light") {
    @Previewable @State var topIndex = 0
    VStack {
        Spacer()
        ReaderToolbar(
            model: ReaderControlsModel(
                chapter: previewChapterRaw,
                bookId: "preview-toolbar",
                variantFamily: .emh,
                preferences: makePrefs(),
                store: makeStore("toolbar-emh")
            ),
            currentTopIndex: topIndex
        )
    }
    .background(Color.cfBackground)
    .ignoresSafeArea()
}

#Preview("Toolbar — With Recommendation") {
    @Previewable @State var topIndex = 0
    let model = ReaderControlsModel(
        chapter: previewChapterRaw,
        bookId: "preview-recommended",
        variantFamily: .emh,
        preferences: makePrefs(),
        store: makeStore("toolbar-rec")
    )
    VStack {
        Spacer()
        ReaderToolbar(model: model, currentTopIndex: topIndex)
    }
    .background(Color.cfBackground)
    .ignoresSafeArea()
    .onAppear { model.recommendedVariant = .hard }
}
#endif
