import Models

extension Fixtures {

    // MARK: - EMH Chapter (with v21Extras)

    /// Chapter + progress for Atomic Habits ch. 1 (EMH family).
    ///
    /// Contains `v21Extras` (hook, counterintuition, tryThisNow, memorable lines,
    /// experience plan) — use this fixture when testing v2.1 reader chrome.
    public static let chapterEMH: ChapterResponse = load("chapter_emh")

    /// Raw `Chapter` from the EMH response.
    public static var chapterEMHChapter: Chapter { chapterEMH.chapter }

    /// `BookProgress` from the EMH response.
    public static var chapterEMHProgress: BookProgress { chapterEMH.progress }

    /// Resolved EMH chapter at `.medium` variant, `.direct` tone.
    public static let resolvedEMH: ResolvedChapter = {
        let response: ChapterResponse = load("chapter_emh")
        return ChapterContentResolver().resolve(
            chapter: response.chapter,
            selectedVariant: .medium,
            selectedTone: .direct
        )
    }()

    // MARK: - PBC Chapter (without v21Extras)

    /// Chapter + progress for Deep Work ch. 1 (PBC family).
    ///
    /// `v21Extras` is `nil` — use this fixture when testing graceful degradation
    /// of reader chrome with legacy content.
    public static let chapterPBC: ChapterResponse = load("chapter_pbc")

    /// Raw `Chapter` from the PBC response.
    public static var chapterPBCChapter: Chapter { chapterPBC.chapter }

    /// `BookProgress` from the PBC response.
    public static var chapterPBCProgress: BookProgress { chapterPBC.progress }

    /// Resolved PBC chapter at `.balanced` variant, `.gentle` tone.
    public static let resolvedPBC: ResolvedChapter = {
        let response: ChapterResponse = load("chapter_pbc")
        return ChapterContentResolver().resolve(
            chapter: response.chapter,
            selectedVariant: .balanced,
            selectedTone: .gentle
        )
    }()

    // MARK: - Concept graph

    /// Concept dependency graph for Atomic Habits.
    public static let conceptGraph: ConceptGraph = load("concept_graph")
}
