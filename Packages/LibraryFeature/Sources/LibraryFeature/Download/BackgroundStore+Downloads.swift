import Foundation
import SwiftData
import Models
import Persistence

// MARK: - Sendable value type for completed download records

/// Lightweight Sendable snapshot used to cross the BackgroundStore actor boundary.
struct BookDownloadRecord: Sendable {
    let bookId: String
    let completedAt: Date?
    let totalBytes: Int64
}

// MARK: - BackgroundStore extensions for DownloadManager

extension BackgroundStore {

    func upsertManifest(_ manifest: BookManifest, userId: String) throws {
        let rowId = CachedManifest.makeRowId(userId: userId, bookId: manifest.bookId)
        let desc = FetchDescriptor<CachedManifest>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        let existing = try modelContext.fetch(desc).first
        if let existing {
            let data = try JSONEncoder().encode(manifest)
            existing.dataJSON = String(bytes: data, encoding: .utf8) ?? ""
            existing.cachedAt = Date()
        } else {
            modelContext.insert(try CachedManifest.from(manifest, userId: userId))
        }
        try modelContext.save()
    }

    func upsertChapter(_ chapter: Chapter, userId: String, bookId: String) throws {
        let rowId = CachedChapter.makeRowId(userId: userId, bookId: bookId, number: chapter.number)
        let desc = FetchDescriptor<CachedChapter>(predicate: #Predicate { $0.rowId == rowId })
        let existing = try modelContext.fetch(desc).first
        if let existing {
            let data = try JSONEncoder().encode(chapter)
            existing.dataJSON = String(bytes: data, encoding: .utf8) ?? ""
            existing.cachedAt = Date()
        } else {
            modelContext.insert(try CachedChapter.from(chapter, userId: userId, bookId: bookId))
        }
        try modelContext.save()
    }

    func upsertQuiz(
        _ quiz: QuizClientSession,
        userId: String,
        bookId: String,
        chapterNumber: Int
    ) throws {
        let rowId = CachedQuizState.makeRowId(
            userId: userId, bookId: bookId, chapterNumber: chapterNumber
        )
        let desc = FetchDescriptor<CachedQuizState>(predicate: #Predicate { $0.rowId == rowId })
        let existing = try modelContext.fetch(desc).first
        if let existing {
            let data = try JSONEncoder().encode(quiz)
            existing.dataJSON = String(bytes: data, encoding: .utf8) ?? ""
            existing.cachedAt = Date()
        } else {
            modelContext.insert(
                try CachedQuizState.from(quiz, userId: userId, bookId: bookId, chapterNumber: chapterNumber)
            )
        }
        try modelContext.save()
    }

    func upsertBookDownload(
        bookId: String,
        userId: String,
        title: String,
        chapterCount: Int
    ) throws {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        let existing = try modelContext.fetch(desc).first
        if let existing {
            existing.title = title
            existing.chapterCount = chapterCount
            existing.status = .downloading
            existing.errorMessage = nil
        } else {
            let record = CachedBookDownload(
                rowId: rowId,
                userId: userId,
                bookId: bookId,
                title: title
            )
            record.chapterCount = chapterCount
            modelContext.insert(record)
        }
        try modelContext.save()
    }

    func incrementDownloadedChapters(bookId: String, userId: String) throws {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        if let record = try modelContext.fetch(desc).first {
            record.downloadedChapterCount += 1
            try modelContext.save()
        }
    }

    func setAudioSegmentCount(bookId: String, userId: String, count: Int) throws {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        if let record = try modelContext.fetch(desc).first {
            record.audioSegmentCount = count
            try modelContext.save()
        }
    }

    func setDownloadedAudioSegmentCount(bookId: String, userId: String, count: Int) throws {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        if let record = try modelContext.fetch(desc).first {
            record.downloadedAudioSegmentCount = count
            try modelContext.save()
        }
    }

    func incrementDownloadedSegments(bookId: String, userId: String) throws {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        if let record = try modelContext.fetch(desc).first {
            record.downloadedAudioSegmentCount += 1
            try modelContext.save()
        }
    }

    func addBytes(bookId: String, userId: String, bytes: Int64) throws {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        if let record = try modelContext.fetch(desc).first {
            record.totalBytes += bytes
            try modelContext.save()
        }
    }

    func markDownloadComplete(bookId: String, userId: String) throws {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        if let record = try modelContext.fetch(desc).first {
            record.status = .downloaded
            record.completedAt = Date()
            try modelContext.save()
        }
    }

    func markDownloadFailed(bookId: String, userId: String, message: String) throws {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        if let record = try modelContext.fetch(desc).first {
            record.status = .failed
            record.errorMessage = message
            try modelContext.save()
        }
    }

    func insertDownloadedSegment(
        segmentId: String,
        bookId: String,
        chapterNumber: Int,
        userId: String,
        fileSize: Int64
    ) throws {
        let existingDesc = FetchDescriptor<CachedDownloadedSegment>(
            predicate: #Predicate { $0.segmentId == segmentId }
        )
        guard (try? modelContext.fetch(existingDesc).isEmpty) == true else { return }
        modelContext.insert(CachedDownloadedSegment(
            segmentId: segmentId,
            bookId: bookId,
            chapterNumber: chapterNumber,
            userId: userId,
            fileSize: fileSize
        ))
        try modelContext.save()
    }

    func segmentIds(bookId: String, userId: String) throws -> [String] {
        let desc = FetchDescriptor<CachedDownloadedSegment>(
            predicate: #Predicate { $0.bookId == bookId && $0.userId == userId }
        )
        return try modelContext.fetch(desc).map(\.segmentId)
    }

    func isDownloaded(bookId: String, userId: String) throws -> Bool {
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        return try modelContext.fetch(desc).first?.status == .downloaded
    }

    func fetchDownloadedBooks(userId: String) throws -> [DownloadedBookInfo] {
        let uid = userId
        let desc = FetchDescriptor<CachedBookDownload>(
            predicate: #Predicate { $0.userId == uid && $0.statusRaw == "downloaded" }
        )
        return try modelContext.fetch(desc).map {
            DownloadedBookInfo(
                bookId: $0.bookId,
                title: $0.title,
                totalBytes: $0.totalBytes,
                downloadedAt: $0.completedAt
            )
        }
    }

    func totalDownloadBytes(userId: String) throws -> Int64 {
        let uid = userId
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.userId == uid })
        return try modelContext.fetch(desc).reduce(0) { $0 + $1.totalBytes }
    }

    func allCompletedDownloads(userId: String) throws -> [BookDownloadRecord] {
        let uid = userId
        let desc = FetchDescriptor<CachedBookDownload>(
            predicate: #Predicate { $0.userId == uid && $0.statusRaw == "downloaded" },
            sortBy: [SortDescriptor(\.completedAt)]
        )
        return try modelContext.fetch(desc).map {
            BookDownloadRecord(bookId: $0.bookId, completedAt: $0.completedAt, totalBytes: $0.totalBytes)
        }
    }

    func deleteBookDownloadRecords(bookId: String, userId: String) throws {
        let uid = userId
        let bid = bookId
        try modelContext.delete(
            model: CachedDownloadedSegment.self,
            where: #Predicate { $0.bookId == bid && $0.userId == uid }
        )
        let rowId = CachedBookDownload.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedBookDownload>(predicate: #Predicate { $0.rowId == rowId })
        if let record = try modelContext.fetch(desc).first {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}
