import Foundation
import Models

/// The metadata passed to `AudioPlayerModel.loadAndPlay(_:)` to start a chapter
/// audio session. Contains everything needed except the signed audio URL, which
/// is fetched asynchronously by the model via `AudioRepository`.
public struct AudioPlaybackRequest: Sendable {
    public let bookId: String
    public let bookTitle: String
    public let bookAuthor: String
    public let chapterNumber: Int
    public let chapterTitle: String
    public let cover: Cover?
    public let totalChapters: Int

    public init(
        bookId: String,
        bookTitle: String,
        bookAuthor: String,
        chapterNumber: Int,
        chapterTitle: String,
        cover: Cover?,
        totalChapters: Int
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.cover = cover
        self.totalChapters = totalChapters
    }
}

/// All context needed to populate Now Playing info and the player UI
/// for a single chapter audio session.
public struct AudioPlaybackItem: Equatable, Sendable {
    public let bookId: String
    public let bookTitle: String
    public let bookAuthor: String
    public let chapterNumber: Int
    public let chapterTitle: String
    public let cover: Cover?
    public let totalChapters: Int
    public let audioURL: URL

    public init(
        bookId: String,
        bookTitle: String,
        bookAuthor: String,
        chapterNumber: Int,
        chapterTitle: String,
        cover: Cover?,
        totalChapters: Int,
        audioURL: URL
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.cover = cover
        self.totalChapters = totalChapters
        self.audioURL = audioURL
    }
}
