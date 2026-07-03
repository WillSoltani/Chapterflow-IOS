import Testing
@testable import ReaderFeature

@Suite("AnnotationModel")
@MainActor
struct AnnotationModelTests {

    // MARK: - Helpers

    private func makeModel(
        variantKey: String = "medium",
        toneKey: String = "gentle"
    ) -> (model: AnnotationModel, repo: FakeAnnotationRepository) {
        let repo = FakeAnnotationRepository()
        let model = AnnotationModel(
            bookId: "book-1",
            chapterId: "ch-1",
            variantKey: variantKey,
            toneKey: toneKey,
            repository: repo
        )
        return (model, repo)
    }

    private func makeAnchor(
        blockIndex: Int,
        variantKey: String = "medium",
        toneKey: String = "gentle"
    ) -> AnnotationAnchor {
        AnnotationAnchor(
            variantKey: variantKey,
            toneKey: toneKey,
            blockIndex: blockIndex,
            blockType: "paragraph",
            startChar: 0,
            endChar: 5,
            snippet: "Hello"
        )
    }

    // MARK: - activeHighlights

    @Test("activeHighlights returns only highlights for the active variant/tone")
    func activeHighlightsFiltersCorrectly() async throws {
        let (model, repo) = makeModel(variantKey: "medium", toneKey: "gentle")

        // Add a highlight in the current variant/tone.
        let matchingAnn = try await repo.addHighlight(
            bookId: "book-1",
            chapterId: "ch-1",
            anchor: makeAnchor(blockIndex: 2, variantKey: "medium", toneKey: "gentle"),
            color: .yellow
        )
        // Add a highlight in a different variant.
        _ = try await repo.addHighlight(
            bookId: "book-1",
            chapterId: "ch-1",
            anchor: makeAnchor(blockIndex: 2, variantKey: "easy", toneKey: "gentle"),
            color: .blue
        )

        await model.load()

        let active = model.activeHighlights(forBlock: 2)
        #expect(active.count == 1)
        #expect(active.first?.annotationId == matchingAnn.annotationId)
    }

    @Test("activeHighlights returns empty when no matching annotations")
    func activeHighlightsEmpty() async {
        let (model, _) = makeModel()
        await model.load()
        #expect(model.activeHighlights(forBlock: 0).isEmpty)
    }

    // MARK: - crossVariantInfo

    @Test("crossVariantInfo returns info when there are highlights in another variant")
    func crossVariantInfoReturnsInfo() async throws {
        let (model, repo) = makeModel(variantKey: "medium", toneKey: "gentle")

        // Highlight in a different variant.
        _ = try await repo.addHighlight(
            bookId: "book-1",
            chapterId: "ch-1",
            anchor: makeAnchor(blockIndex: 3, variantKey: "easy", toneKey: "direct"),
            color: .pink
        )
        await model.load()

        let info = model.crossVariantInfo(forBlock: 3)
        #expect(info != nil)
        #expect(info?.count == 1)
        #expect(info?.variantKey == "easy")
        #expect(info?.toneKey == "direct")
    }

    @Test("crossVariantInfo returns nil when there are no other-variant highlights")
    func crossVariantInfoNil() async {
        let (model, _) = makeModel()
        await model.load()
        #expect(model.crossVariantInfo(forBlock: 0) == nil)
    }

    // MARK: - createHighlight

    @Test("createHighlight appends an annotation after the async repository call")
    func createHighlightAppends() async {
        let (model, _) = makeModel()
        await model.load()
        #expect(model.annotations.isEmpty)

        model.createHighlight(
            blockIndex: 1,
            blockText: "Hello",
            blockType: "paragraph",
            color: .yellow
        )

        // The Task inside createHighlight runs concurrently; yield to let it complete.
        await Task.yield()
        await Task.yield()

        #expect(model.annotations.count == 1)
        #expect(model.annotations.first?.type == "highlight")
        #expect(model.annotations.first?.colorRaw == "yellow")
    }

    // MARK: - deleteAnnotation

    @Test("deleteAnnotation removes the annotation optimistically")
    func deleteRemovesAnnotation() async throws {
        let (model, repo) = makeModel()
        let ann = try await repo.addHighlight(
            bookId: "book-1",
            chapterId: "ch-1",
            anchor: makeAnchor(blockIndex: 0),
            color: .green
        )
        await model.load()
        #expect(model.annotations.count == 1)

        model.deleteAnnotation(ann)
        #expect(model.annotations.isEmpty)
    }

    // MARK: - updateVariantTone

    @Test("updateVariantTone changes the active filter")
    func updateVariantToneChangesFilter() async throws {
        let (model, repo) = makeModel(variantKey: "medium", toneKey: "gentle")

        // Highlight in the NEW variant (not yet active).
        _ = try await repo.addHighlight(
            bookId: "book-1",
            chapterId: "ch-1",
            anchor: makeAnchor(blockIndex: 0, variantKey: "easy", toneKey: "direct"),
            color: .blue
        )
        await model.load()

        // Before switch: no active highlights on block 0.
        #expect(model.activeHighlights(forBlock: 0).isEmpty)

        // After switching to "easy"/"direct", the highlight should be visible.
        model.updateVariantTone(variant: "easy", tone: "direct")
        #expect(model.activeHighlights(forBlock: 0).count == 1)
    }

    // MARK: - hasBookmark

    @Test("hasBookmark reflects bookmark presence")
    func hasBookmarkReflectsState() async {
        let (model, _) = makeModel()
        await model.load()
        #expect(model.hasBookmark == false)

        model.toggleBookmark()
        // Yield twice to let the internal Task complete.
        await Task.yield()
        await Task.yield()

        #expect(model.hasBookmark == true)
    }

    // MARK: - Note editor flow

    @Test("beginAddingNote sets isShowingNoteEditor")
    func beginAddingNoteShowsEditor() async {
        let (model, _) = makeModel()
        #expect(model.isShowingNoteEditor == false)
        model.beginAddingNote(blockIndex: 0, blockText: "Hello", blockType: "paragraph")
        #expect(model.isShowingNoteEditor == true)
    }

    @Test("saveNote with empty content does not append annotation")
    func saveNoteEmptyNoOp() async {
        let (model, _) = makeModel()
        model.beginAddingNote(blockIndex: 0, blockText: "Hello", blockType: "paragraph")
        model.saveNote(content: "")
        await Task.yield()
        #expect(model.annotations.isEmpty)
    }
}
