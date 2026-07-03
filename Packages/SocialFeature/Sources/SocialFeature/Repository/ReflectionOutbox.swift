import Foundation
import os

/// A file-backed, actor-isolated outbox for offline-queued chapter reflections.
///
/// Write once, sync-when-ready: every `PendingReflectionItem` added here is
/// persisted to disk immediately so it survives app restarts. The outbox is
/// internal to `SocialFeature`; consumers interact through `SocialRepository`.
actor ReflectionOutbox {

    private var items: [PendingReflectionItem] = []
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "ReflectionOutbox")

    init() {
        let appSupport: URL
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            appSupport = dir.appending(path: "ChapterFlow", directoryHint: .isDirectory)
        } else {
            appSupport = FileManager.default.temporaryDirectory
        }
        fileURL = appSupport.appending(path: "pending_reflections.json")

        // Ensure directory exists.
        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        // Load persisted items.
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder.chapterFlow.decode([PendingReflectionItem].self, from: data) {
            items = loaded
        }
    }

    /// Test-only initializer with an explicit file URL so tests don't touch the real app storage.
    init(fileURL: URL) {
        self.fileURL = fileURL
        // No existing items in a fresh temp file.
    }

    // MARK: - Query

    func all(bookId: String, chapterN: Int) -> [PendingReflectionItem] {
        items.filter { $0.bookId == bookId && $0.chapterN == chapterN }
    }

    // MARK: - Mutations

    func append(_ item: PendingReflectionItem) {
        items.append(item)
        persist()
    }

    func update(_ updated: PendingReflectionItem) {
        guard let idx = items.firstIndex(where: { $0.localId == updated.localId }) else { return }
        items[idx] = updated
        persist()
    }

    func markFeedbackPending(localId: String) {
        guard let idx = items.firstIndex(where: { $0.localId == localId }) else { return }
        items[idx].feedbackState = .pending
        persist()
    }

    func markFeedbackReceived(localId: String, feedbackText: String) {
        guard let idx = items.firstIndex(where: { $0.localId == localId }) else { return }
        items[idx].feedbackState = .received
        items[idx].feedbackText = feedbackText
        persist()
    }

    func remove(localId: String) {
        items.removeAll { $0.localId == localId }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.warning("Failed to persist reflection outbox: \(error.localizedDescription)")
        }
    }
}
