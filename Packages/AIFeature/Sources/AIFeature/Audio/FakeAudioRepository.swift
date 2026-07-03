import Foundation
import CoreKit

/// In-memory ``AudioRepository`` for unit tests and SwiftUI previews.
///
/// Returns a silent local audio URL by default, or a forced error when
/// configured with one.
public actor FakeAudioRepository: AudioRepository {

    private let forcedError: AppError?
    private let delay: Double

    public init(error: AppError? = nil, delay: Double = 0.0) {
        self.forcedError = error
        self.delay = delay
    }

    public func chapterAudioURL(bookId: String, chapterNumber: Int) async throws -> URL {
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        if let error = forcedError { throw error }
        // Return a valid-but-silent URL so previews can exercise the player model
        // without a real network request. AVPlayer handles a missing resource gracefully.
        return URL(string: "https://audio.chapterflow.app/preview/sample.m4a")!
    }
}
