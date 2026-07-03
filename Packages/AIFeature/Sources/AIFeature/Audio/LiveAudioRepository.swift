import Foundation
import Networking
import CoreKit

/// Production ``AudioRepository`` that resolves chapter audio URLs from the
/// ChapterFlow REST API.
public actor LiveAudioRepository: AudioRepository {

    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func chapterAudioURL(bookId: String, chapterNumber: Int) async throws -> URL {
        let endpoint = Endpoints.getChapterAudio(bookId: bookId, chapterNumber: chapterNumber)
        let response: ChapterAudio = try await client.send(endpoint)
        guard let url = URL(string: response.url) else {
            throw AppError.decoding(URLError(.badURL))
        }
        return url
    }
}
