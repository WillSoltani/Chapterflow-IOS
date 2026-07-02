// Models — Codable domain models + pure business logic for ChapterFlow.
//
// Key entry points:
//   ChapterContentResolver  — resolve (chapter, variant, tone) → ResolvedChapter
//   EntitlementEvaluator    — pure gating logic (isPro, canStart, isChapterUnlocked)
//   JSONDecoder.chapterFlow — shared decoder for all API responses
