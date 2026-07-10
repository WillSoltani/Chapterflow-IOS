import Testing
import Foundation
@testable import Models

// MARK: - Real-contract fixtures
//
// These fixtures are VERBATIM captures from the deployed production API
// (app.chapterflow.ca, captured 2026-07-10, deploy sha 19b44fac). They are the
// ground truth for the client ↔ server contract reconciliation:
// docs/API-CONTRACT-MISMATCH-AND-RECONCILIATION-PLAN.md.
//
// Refresh them with `scripts/refresh-fixtures.sh` (public endpoints need no
// token). If one of these tests fails after a refresh, the server has drifted
// again — fix the model tolerantly, never by hand-editing the capture.

private func prodFixture(_ name: String) throws -> Data {
    guard
        let url = Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Resources")
    else {
        throw NSError(
            domain: "RealContractTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name).json"])
    }
    return try Data(contentsOf: url)
}

@Suite("Real production contract — GET /book/books")
struct ProdCatalogContractTests {

    @Test("the full deployed catalog decodes without dropping a single book")
    func fullCatalogDecodes() throws {
        let data = try prodFixture("prod_catalog")
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        // The capture holds 110 published books; every one must survive.
        // (Count asserted against the raw JSON so a lossy drop can't hide.)
        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rawCount = (raw["books"] as! [Any]).count
        #expect(rawCount > 0)
        #expect(response.books.count == rawCount)
    }

    @Test("web-shaped keys map onto the canonical model")
    func webShapeMapping() throws {
        let data = try prodFixture("prod_catalog")
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        let book = try #require(response.books.first { $0.bookId == "seven-powers" })
        #expect(book.title.hasPrefix("7 Powers"))
        #expect(book.author == "Hamilton Helmer")
        // `publishedVersion` feeds both version fields.
        #expect(book.latestVersion == book.currentPublishedVersion)
        #expect(book.latestVersion != nil)
        // `icon` synthesizes the emoji cover; `coverImage` is preserved.
        #expect(book.cover?.emoji?.isEmpty == false)
        #expect(book.coverImageURL?.contains("covers/seven-powers") == true)
        // Web shape adds chapterCount; absent fields stay nil, never throw.
        #expect(book.chapterCount ?? 0 > 0)
        #expect(book.status == nil)
        #expect(book.updatedAt == nil)
    }

    @Test("every deployed book has a usable identity, title, and cover emoji")
    func everyBookUsable() throws {
        let data = try prodFixture("prod_catalog")
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        for book in response.books {
            #expect(!book.bookId.isEmpty)
            #expect(!book.title.isEmpty)
            #expect(book.cover?.emoji?.isEmpty == false)
        }
    }
}

@Suite("Real production contract — GET /book/search-index")
struct ProdSearchIndexContractTests {

    @Test("the deployed bare-array envelope decodes")
    func bareArrayDecodes() throws {
        let data = try prodFixture("prod_search_index")
        let response = try JSONDecoder.chapterFlow.decode(SearchIndexResponse.self, from: data)
        let rawCount = (try JSONSerialization.jsonObject(with: data) as! [Any]).count
        #expect(rawCount > 0)
        #expect(response.books.count == rawCount)
    }

    @Test("bookTitle maps to title; bookId is the identity")
    func fieldMapping() throws {
        let data = try prodFixture("prod_search_index")
        let response = try JSONDecoder.chapterFlow.decode(SearchIndexResponse.self, from: data)
        let entry = try #require(response.books.first { $0.bookId == "atomic-habits" })
        #expect(entry.title == "Atomic Habits")
        #expect(entry.author == "James Clear")
        #expect(entry.chapters.isEmpty) // deployed index carries no chapter list
    }

    @Test("the canonical {books:[…]} envelope still decodes (cache compatibility)")
    func canonicalEnvelopeStillDecodes() throws {
        let canonical = Data(
            #"{"books":[{"bookId":"b1","title":"T","author":"A"}]}"#.utf8)
        let response = try JSONDecoder.chapterFlow.decode(
            SearchIndexResponse.self, from: canonical)
        #expect(response.books.count == 1)
        #expect(response.books[0].title == "T")
    }
}

@Suite("Real production contract — GET /book/books/{id}")
struct ProdBookDetailContractTests {

    @Test("the deployed {book:{…}} wrapper decodes into BookManifest")
    func wrappedManifestDecodes() throws {
        let data = try prodFixture("prod_book_detail")
        let manifest = try JSONDecoder.chapterFlow.decode(BookManifest.self, from: data)
        #expect(manifest.bookId == "seven-powers")
        #expect(manifest.chapters.count == 9)
        #expect(manifest.description?.isEmpty == false)  // ← synopsis
        #expect(manifest.totalReadingTimeMinutes == 108) // ← estimatedMinutes
        #expect(manifest.chapterCount == 9)
        #expect(manifest.cover?.emoji?.isEmpty == false) // ← icon
    }

    @Test("chapter entries map minutes → readingTimeMinutes and keep numbering")
    func chapterMapping() throws {
        let data = try prodFixture("prod_book_detail")
        let manifest = try JSONDecoder.chapterFlow.decode(BookManifest.self, from: data)
        for (index, chapter) in manifest.chapters.enumerated() {
            #expect(chapter.number == index + 1)
            #expect(!chapter.chapterId.isEmpty)
            #expect(chapter.readingTimeMinutes > 0) // wire key is `minutes`
            #expect(!chapter.title.isEmpty)
        }
    }

    @Test("the canonical BARE manifest still decodes (cache compatibility)")
    func canonicalBareStillDecodes() throws {
        let canonical = Data("""
        {"bookId":"b1","title":"T","author":"A","categories":[],"tags":[],
         "cover":null,"variantFamily":"EMH","status":"published","latestVersion":2,
         "currentPublishedVersion":2,"updatedAt":"2024-01-01T00:00:00Z",
         "chapters":[{"chapterId":"c1","number":1,"title":"One",
                      "readingTimeMinutes":10,"chapterKey":null,"quizKey":null}]}
        """.utf8)
        let manifest = try JSONDecoder.chapterFlow.decode(BookManifest.self, from: canonical)
        #expect(manifest.bookId == "b1")
        #expect(manifest.status == "published")
        #expect(manifest.latestVersion == 2)
        #expect(manifest.chapters.first?.readingTimeMinutes == 10)
    }

    @Test("encode → decode round-trips through the canonical shape")
    func encodeRoundTrip() throws {
        let data = try prodFixture("prod_book_detail")
        let manifest = try JSONDecoder.chapterFlow.decode(BookManifest.self, from: data)
        let encoded = try JSONEncoder().encode(manifest)
        // Canonical encoding must not emit the `book` wrapper or web keys…
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["book"] == nil)
        #expect(object["bookId"] as? String == "seven-powers")
        #expect(object["publishedVersion"] == nil)
        // …and must decode back losslessly (the cached-data path).
        let redecoded = try JSONDecoder.chapterFlow.decode(BookManifest.self, from: encoded)
        #expect(redecoded.bookId == manifest.bookId)
        #expect(redecoded.chapters.count == manifest.chapters.count)
        #expect(redecoded.totalReadingTimeMinutes == manifest.totalReadingTimeMinutes)
    }
}

@Suite("Real production contract — GET /book/me/progress (deployed shape)")
struct ProdProgressContractTests {

    // Derived from the deployed serializer app/app/api/book/me/progress/route.ts:44-54
    // (authed endpoint — shape verified against deployed code at sha 19b44fac).
    private let deployedShape = Data("""
    {"summary":{"totalBooks":2,"activeBooks":1},
     "books":[
       {"bookId":"atomic-habits","pinnedBookVersion":3,"currentChapterNumber":4,
        "unlockedThroughChapterNumber":4,"completedChapters":[1,2,3],
        "bestScoreByChapter":{"1":100,"2":80,"3":90},
        "lastOpenedAt":"2026-07-09T18:00:00Z","lastActiveAt":"2026-07-09T18:30:00Z",
        "updatedAt":"2026-07-09T18:30:01Z"},
       {"bookId":"deep-work","currentChapterNumber":1,
        "unlockedThroughChapterNumber":1,"completedChapters":[],
        "bestScoreByChapter":{}}
     ]}
    """.utf8)

    @Test("the deployed {summary, books} envelope decodes")
    func deployedEnvelopeDecodes() throws {
        let response = try JSONDecoder.chapterFlow.decode(
            ProgressOverviewResponse.self, from: deployedShape)
        #expect(response.progress.count == 2)
    }

    @Test("completedChapters array derives the completed count; lastOpenedAt maps to lastReadAt")
    func fieldDerivation() throws {
        let response = try JSONDecoder.chapterFlow.decode(
            ProgressOverviewResponse.self, from: deployedShape)
        let item = try #require(response.progress.first { $0.bookId == "atomic-habits" })
        #expect(item.completedChapterCount == 3)
        #expect(item.currentChapterNumber == 4)
        #expect(item.lastReadAt == "2026-07-09T18:00:00Z")
        // No totals on the wire → 0, and the hint-based fraction takes over.
        #expect(item.totalChapters == 0)
        #expect(item.completionFraction == 0)
        #expect(item.completionFraction(totalChapterHint: 6) == 0.5)
    }

    @Test("the canonical {progress:[…]} envelope still decodes (cache compatibility)")
    func canonicalEnvelopeStillDecodes() throws {
        let canonical = Data("""
        {"progress":[{"bookId":"b1","currentChapterNumber":2,"totalChapters":10,
                      "completedChapterCount":1,"lastReadAt":"2026-01-01T00:00:00Z"}]}
        """.utf8)
        let response = try JSONDecoder.chapterFlow.decode(
            ProgressOverviewResponse.self, from: canonical)
        #expect(response.progress.count == 1)
        #expect(response.progress[0].totalChapters == 10)
        #expect(response.progress[0].completionFraction == 0.1)
    }
}
