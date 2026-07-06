import Foundation

/// Snapshot of a book-download operation's current progress.
public struct DownloadProgress: Sendable {
    public let bookId: String
    public let phase: Phase
    /// 0.0 – 1.0; computed from chapters + audio segments completed.
    public let fractionCompleted: Double

    public enum Phase: Sendable {
        case fetchingManifest
        case downloadingChapters(current: Int, total: Int)
        case downloadingAudio(current: Int, total: Int)
        case complete
        case failed(String)
    }

    public init(bookId: String, phase: Phase, fractionCompleted: Double) {
        self.bookId = bookId
        self.phase = phase
        self.fractionCompleted = fractionCompleted
    }
}
