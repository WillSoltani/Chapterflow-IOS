import Foundation

// MARK: - Download-specific endpoint extensions
//
// These endpoints exist separately from Endpoint.swift to keep that file
// under the 600-line cap.  All four are used by DownloadManager at download
// time; they MUST NOT be used for normal online reads (use the originals instead).

public extension Endpoints {

    /// Re-fetches the book manifest to get the current chapter list.
    /// Called once per `downloadBook` to seed the download plan.
    static func getManifestForDownload(bookId: String) -> Endpoint {
        Endpoint(method: .get, path: "/book/books/\(bookId)", requiresAuth: false)
    }

    /// Fetches full chapter content (all depth variants + tones) for offline storage.
    /// The server always returns `contentVariants` for all variants so a single
    /// request captures everything needed for variant-switching offline.
    static func getChapterForDownload(bookId: String, chapterNumber: Int) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/book/books/\(bookId)/chapters/\(chapterNumber)",
            requiresAuth: true
        )
    }

    /// Fetches the chapter quiz for offline storage.
    static func getQuizForDownload(bookId: String, chapterNumber: Int) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/book/books/\(bookId)/chapters/\(chapterNumber)/quiz",
            requiresAuth: true
        )
    }

    /// Re-fetches the audio narration plan to get fresh presigned segment URLs.
    ///
    /// Presigned URLs expire after a short window; this endpoint MUST be called
    /// immediately before downloading that chapter's audio segments — never cache
    /// the presigned URLs across sessions or resume attempts.
    static func getAudioPlanFreshURLs(bookId: String, chapterNumber: Int) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/book/books/\(bookId)/chapters/\(chapterNumber)/audio",
            query: [URLQueryItem(name: "mode", value: "plan")],
            requiresAuth: true
        )
    }
}
