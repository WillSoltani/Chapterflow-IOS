import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - NotebookModel Tests

@Suite("NotebookModel — filtering")
@MainActor
struct NotebookModelTests {

    private func makeModel() -> NotebookModel {
        NotebookModel.preview  // Uses preloaded fixture data
    }

    @Test("filteredEntries returns all when no filters set")
    func noFiltersReturnsAll() {
        let model = makeModel()
        #expect(model.filteredEntries.count == NotebookEntry.previewEntries.count)
    }

    @Test("searchText filters by content")
    func searchByContent() {
        let model = makeModel()
        model.searchText = "deep work"
        let results = model.filteredEntries
        #expect(results.allSatisfy {
            $0.content?.lowercased().contains("deep work") == true
            || $0.quote?.lowercased().contains("deep work") == true
            || $0.bookTitle?.lowercased().contains("deep work") == true
        })
    }

    @Test("searchText filters by book title")
    func searchByBookTitle() {
        let model = makeModel()
        model.searchText = "Atomic Habits"
        let results = model.filteredEntries
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.bookTitle == "Atomic Habits" })
    }

    @Test("searchText is case-insensitive")
    func searchCaseInsensitive() {
        let model = makeModel()
        model.searchText = "atomic habits"
        let lowerResults = model.filteredEntries.count
        model.searchText = "ATOMIC HABITS"
        let upperResults = model.filteredEntries.count
        #expect(lowerResults == upperResults)
    }

    @Test("selectedTypeFilter filters by type")
    func typeFilter() {
        let model = makeModel()
        model.selectedTypeFilter = .note
        let results = model.filteredEntries
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.type == .note })
    }

    @Test("selectedTypeFilter = nil returns all types")
    func typeFilterNilReturnsAll() {
        let model = makeModel()
        model.selectedTypeFilter = .note
        model.selectedTypeFilter = nil
        #expect(model.filteredEntries.count == NotebookEntry.previewEntries.count)
    }

    @Test("selectedTags filters by matching tags")
    func tagFilter() {
        let model = makeModel()
        model.selectedTags = ["habits"]
        let results = model.filteredEntries
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.effectiveTags.contains("habits") })
    }

    @Test("selectedTags uses OR logic (any matching tag)")
    func tagFilterOrLogic() {
        let model = makeModel()
        model.selectedTags = ["habits", "focus"]
        let results = model.filteredEntries
        #expect(!results.isEmpty)
        for entry in results {
            let tags = Set(entry.effectiveTags)
            #expect(!tags.isDisjoint(with: ["habits", "focus"]))
        }
    }

    @Test("availableTags contains unique tags from all entries")
    func availableTagsUnique() {
        let model = makeModel()
        let tags = model.availableTags
        // Must be unique
        #expect(Set(tags).count == tags.count)
        // Must be sorted
        #expect(tags == tags.sorted())
    }

    @Test("clearFilters resets all filter state")
    func clearFilters() {
        let model = makeModel()
        model.searchText = "deep work"
        model.selectedTypeFilter = .note
        model.selectedTags = ["habits"]
        model.clearFilters()
        #expect(model.searchText.isEmpty)
        #expect(model.selectedTypeFilter == nil)
        #expect(model.selectedTags.isEmpty)
        #expect(!model.hasActiveFilters)
    }

    @Test("toggleTag adds and removes tags")
    func toggleTag() {
        let model = makeModel()
        model.toggleTag("habits")
        #expect(model.selectedTags.contains("habits"))
        model.toggleTag("habits")
        #expect(!model.selectedTags.contains("habits"))
    }

    @Test("hasActiveFilters detects active search text")
    func hasActiveFiltersSearchText() {
        let model = makeModel()
        #expect(!model.hasActiveFilters)
        model.searchText = "  test  "
        #expect(model.hasActiveFilters)
    }

    @Test("filteredEntries sorted most-recent-first")
    func sortedByDate() {
        let model = makeModel()
        let entries = model.filteredEntries
        let dates = entries.map(\.updatedAt)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("deleteEntry removes entry optimistically")
    func deleteEntryOptimistic() async {
        let model = makeModel()
        let initial = model.allEntries.count
        let target = model.allEntries[0].entryId
        await model.deleteEntry(entryId: target)
        #expect(model.allEntries.count == initial - 1)
        #expect(!model.allEntries.map(\.entryId).contains(target))
    }
}

// MARK: - NotebookEntry effectiveTags

@Suite("NotebookEntry — effectiveTags")
struct NotebookEntryEffectiveTagsTests {

    @Test("effectiveTags returns empty when tags is nil")
    func effectiveTagsNil() {
        let entry = NotebookEntry(
            entryId: "x", bookId: "b", chapterId: nil, type: .note,
            content: nil, quote: nil, createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            bookTitle: nil, chapterTitle: nil, chapterNumber: nil, tags: nil
        )
        #expect(entry.effectiveTags.isEmpty)
    }

    @Test("effectiveTags filters whitespace-only tags")
    func effectiveTagsFiltersWhitespace() {
        let entry = NotebookEntry(
            entryId: "x", bookId: "b", chapterId: nil, type: .note,
            content: nil, quote: nil, createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            bookTitle: nil, chapterTitle: nil, chapterNumber: nil, tags: ["   ", "valid", ""]
        )
        #expect(entry.effectiveTags == ["valid"])
    }

    @Test("effectiveTags preserves non-empty tags")
    func effectiveTagsPreservesValid() {
        let entry = NotebookEntry(
            entryId: "x", bookId: "b", chapterId: nil, type: .note,
            content: nil, quote: nil, createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            bookTitle: nil, chapterTitle: nil, chapterNumber: nil, tags: ["alpha", "beta"]
        )
        #expect(entry.effectiveTags == ["alpha", "beta"])
    }
}

// MARK: - NotebookEntry decoding evolution

@Suite("NotebookEntry — server evolution")
struct NotebookEntryEvolutionTests {

    @Test("unknown entry type decodes to .unknown without crashing")
    func unknownType() throws {
        let json = """
        {
          "entryId": "e1",
          "bookId": "b1",
          "type": "future_type_xyz",
          "createdAt": "2026-07-01T00:00:00Z",
          "updatedAt": "2026-07-01T00:00:00Z"
        }
        """
        let entry = try JSONCoding.decoder.decode(
            NotebookEntry.self,
            from: json.data(using: .utf8)!
        )
        if case .unknown(let raw) = entry.type {
            #expect(raw == "future_type_xyz")
        } else {
            Issue.record("Expected .unknown, got \(entry.type)")
        }
    }

    @Test("extra JSON fields are ignored")
    func extraFields() throws {
        let json = """
        {
          "entryId": "e2",
          "bookId": "b2",
          "type": "note",
          "content": "hello",
          "createdAt": "2026-07-01T00:00:00Z",
          "updatedAt": "2026-07-01T00:00:00Z",
          "futureField": "someValue",
          "anotherFuture": 42
        }
        """
        let entry = try JSONCoding.decoder.decode(
            NotebookEntry.self,
            from: json.data(using: .utf8)!
        )
        #expect(entry.content == "hello")
    }

    @Test("optional fields default to nil when absent")
    func optionalFieldsAbsent() throws {
        let json = """
        {
          "entryId": "e3",
          "bookId": "b3",
          "type": "bookmark",
          "createdAt": "2026-07-01T00:00:00Z",
          "updatedAt": "2026-07-01T00:00:00Z"
        }
        """
        let entry = try JSONCoding.decoder.decode(
            NotebookEntry.self,
            from: json.data(using: .utf8)!
        )
        #expect(entry.chapterId == nil)
        #expect(entry.content == nil)
        #expect(entry.quote == nil)
        #expect(entry.bookTitle == nil)
        #expect(entry.chapterNumber == nil)
        #expect(entry.tags == nil)
    }

    @Test("NotebookResponse decodes lossily — one bad element is dropped")
    func lossyDecoding() throws {
        let json = """
        {
          "entries": [
            {
              "entryId": "good",
              "bookId": "b1",
              "type": "note",
              "createdAt": "2026-07-01T00:00:00Z",
              "updatedAt": "2026-07-01T00:00:00Z"
            },
            null,
            {
              "entryId": "also-good",
              "bookId": "b2",
              "type": "bookmark",
              "createdAt": "2026-07-01T00:00:00Z",
              "updatedAt": "2026-07-01T00:00:00Z"
            }
          ]
        }
        """
        let resp = try JSONCoding.decoder.decode(
            NotebookResponse.self,
            from: json.data(using: .utf8)!
        )
        // null entry dropped; two valid entries survive
        #expect(resp.entries.count == 2)
        #expect(resp.entries.map(\.entryId) == ["good", "also-good"])
    }
}
