import ActivityKit
import Foundation

// MARK: - ReadingSessionAttributes
//
// Compiled by BOTH the ChapterFlow app target AND the ChapterflowWidgets
// extension target. The app starts/updates the activity; the extension renders it.
// Keep this file's content minimal and Sendable-safe.

/// Describes a live reading or audio narration session.
public struct ReadingSessionAttributes: ActivityAttributes, Sendable {
    public typealias ContentState = ReadingSessionStatus

    // MARK: - Static (set at start, never change)

    /// Display title of the book being read/listened to.
    public let bookTitle: String
    /// Emoji glyph for the book cover (e.g. "⚛️").
    public let bookEmoji: String
    /// Hex colour string for the book cover background (e.g. "#3A86FF").
    public let bookColor: String
    /// 1-based chapter number.
    public let chapterNumber: Int
    /// Chapter title string.
    public let chapterTitle: String
    /// Whether the session is a text reading or audio narration.
    public let sessionKind: SessionKind

    public enum SessionKind: String, Codable, Hashable, Sendable {
        case reading
        case audio
    }

    public init(
        bookTitle: String,
        bookEmoji: String,
        bookColor: String,
        chapterNumber: Int,
        chapterTitle: String,
        sessionKind: SessionKind
    ) {
        self.bookTitle = bookTitle
        self.bookEmoji = bookEmoji
        self.bookColor = bookColor
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.sessionKind = sessionKind
    }
}

// MARK: - ReadingSessionStatus (dynamic, updated live)

public struct ReadingSessionStatus: Codable, Hashable, Sendable {
    /// Seconds elapsed since the session started.
    public var elapsedSeconds: Int
    /// Fraction of chapter read/listened to (0…1).
    public var chapterProgress: Double
    /// For audio sessions: whether playback is currently active.
    public var isPlaying: Bool
    /// Whether the user's daily reading streak is at risk.
    public var streakAtRisk: Bool

    public init(
        elapsedSeconds: Int,
        chapterProgress: Double,
        isPlaying: Bool,
        streakAtRisk: Bool
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.chapterProgress = max(0, min(1, chapterProgress))
        self.isPlaying = isPlaying
        self.streakAtRisk = streakAtRisk
    }

    // MARK: - Derived helpers (not stored — computed for the UI)

    /// Human-readable elapsed time string, e.g. "12:34".
    public var elapsedString: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Progress percentage 0–100 (integer, for display).
    public var progressPercent: Int { Int(chapterProgress * 100) }
}
