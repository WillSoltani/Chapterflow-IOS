import Testing
import Foundation
@testable import Models

// MARK: - GET/POST /book/me/saved contract
//
// The deployed route (app/app/api/book/me/saved/route.ts) responds
// `{"saved": [<BookUserSavedBookItem>…], "savedBookIds": [String]}` —
// `savedBookIds` was added 2026-07-11 (web PR #399) after the strict decode of
// the `saved`-only shape errored Home/Library on device. The row literal below
// mirrors the server's `listSavedBooks` projection (repo.ts): {userId, bookId,
// savedAt, updatedAt, source?, priority?, pinned}.

@Suite("Deployed contract — saved books")
struct SavedBooksContractTests {

    private let decoder = JSONDecoder()

    /// The exact pre-2026-07-11 deployed shape (only `saved`, rows are objects)
    /// — the shape that used to throw keyNotFound(savedBookIds) and take down
    /// Home + Library. It must decode by deriving ids from `saved[].bookId`.
    @Test func legacyDeployedShape_savedObjectsOnly_decodes() throws {
        let json = Data("""
        {"saved":[{"userId":"a4089498-1031-70e9-8ac9-e373f2563c55","bookId":"the-art-of-war","savedAt":"2026-06-18T07:20:00.000Z","updatedAt":"2026-06-18T07:20:00.000Z","pinned":false}]}
        """.utf8)
        let resp = try decoder.decode(SavedBooksResponse.self, from: json)
        #expect(resp.savedBookIds == ["the-art-of-war"])
    }

    /// The current deployed shape carries BOTH keys; canonical `savedBookIds`
    /// wins (order and content come from it verbatim).
    @Test func currentDeployedShape_bothKeys_canonicalWins() throws {
        let json = Data("""
        {"saved":[{"bookId":"ignored-when-canonical-present"}],"savedBookIds":["atomic-habits","deep-work"]}
        """.utf8)
        let resp = try decoder.decode(SavedBooksResponse.self, from: json)
        #expect(resp.savedBookIds == ["atomic-habits", "deep-work"])
    }

    @Test func canonicalOnly_decodes() throws {
        let resp = try decoder.decode(
            SavedBooksResponse.self, from: Data(#"{"savedBookIds":[]}"#.utf8))
        #expect(resp.savedBookIds.isEmpty)
    }

    /// Neither key → empty, never a throw (an empty shelf must not error the
    /// Library screen).
    @Test func neitherKey_decodesEmpty() throws {
        let resp = try decoder.decode(SavedBooksResponse.self, from: Data("{}".utf8))
        #expect(resp.savedBookIds.isEmpty)
    }

    /// A `saved` row without a bookId is dropped lossily; the rest survive.
    @Test func savedRowWithoutBookId_droppedLossily() throws {
        let json = Data("""
        {"saved":[{"userId":"u1"},{"bookId":"mastery"},42]}
        """.utf8)
        let resp = try decoder.decode(SavedBooksResponse.self, from: json)
        #expect(resp.savedBookIds == ["mastery"])
    }

    /// Encoding stays canonical (`savedBookIds` only) so SwiftData/UserDefaults
    /// caches written by this build re-decode via the canonical branch.
    @Test func encode_isCanonical_roundTrips() throws {
        let original = SavedBooksResponse(savedBookIds: ["blink"])
        let data = try JSONEncoder().encode(original)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj.keys.sorted() == ["savedBookIds"])
        let redecoded = try decoder.decode(SavedBooksResponse.self, from: data)
        #expect(redecoded.savedBookIds == ["blink"])
    }
}
