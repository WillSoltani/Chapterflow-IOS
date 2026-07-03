import Foundation
import Models
import Networking
import CoreKit

/// Production ``AudioRepository`` — calls the ChapterFlow REST API and
/// downloads segment assets using `URLSession`.
public actor LiveAudioRepository: AudioRepository {

    private let client: any APIClientProtocol
    private let session: URLSession

    public init(client: any APIClientProtocol, session: URLSession = .shared) {
        self.client = client
        self.session = session
    }

    // MARK: - AudioRepository

    public func fetchPlan(bookId: String, chapterNumber: Int) async throws -> AudioNarrationPlan {
        let endpoint = Endpoints.getAudioPlan(bookId: bookId, chapterNumber: chapterNumber)
        let response: AudioNarrationResponse = try await client.send(endpoint)
        return response.plan
    }

    public func downloadSegment(
        remoteURL: URL,
        segmentId: String,
        to directory: URL
    ) async throws -> URL {
        let localURL = directory.appending(path: "\(segmentId).mp3")
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        let (tempURL, response) = try await session.download(from: remoteURL)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw AppError.server(code: "presigned_url_expired", message: "Segment URL expired", requestId: nil)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        return localURL
    }

    public nonisolated func localURL(for segmentId: String, in directory: URL) -> URL? {
        let url = directory.appending(path: "\(segmentId).mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func postAudioSessionEvent(
        event: String,
        bookId: String,
        chapterNumber: Int,
        sessionId: String?,
        listeningSeconds: Double?
    ) async throws {
        let endpoint = try Endpoints.postAudioSessionEvent(
            event: event,
            bookId: bookId,
            chapterNumber: chapterNumber,
            sessionId: sessionId,
            listeningSeconds: listeningSeconds
        )
        // Best-effort: ignore the response body (server returns a session record)
        let _: SessionEventResponse = try await client.send(endpoint)
    }
}

/// Minimal decodable for the reading-session event response (any shape is fine).
private struct SessionEventResponse: Decodable {}
