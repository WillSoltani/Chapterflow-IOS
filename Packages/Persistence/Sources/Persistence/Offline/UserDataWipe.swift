import Foundation
import SwiftData

// MARK: - UserDataWipe

/// Deletes all cached rows and pending mutations owned by a given user.
///
/// Called on sign-out. Leaves rows belonging to other users intact
/// (relevant when the device is shared or has multiple accounts).
public enum UserDataWipe {
    /// Deletes every offline-schema row for `userId` from `context` and saves.
    ///
    /// This is a synchronous main-actor operation. For background wipes,
    /// use ``BackgroundStore.wipeUserData(userId:)``.
    @MainActor
    public static func wipe(userId: String, context: ModelContext) throws {
        let uid = userId
        try context.delete(model: CachedBook.self,
                           where: #Predicate<CachedBook> { $0.userId == uid })
        try context.delete(model: CachedChapter.self,
                           where: #Predicate<CachedChapter> { $0.userId == uid })
        try context.delete(model: CachedManifest.self,
                           where: #Predicate<CachedManifest> { $0.userId == uid })
        try context.delete(model: CachedProgress.self,
                           where: #Predicate<CachedProgress> { $0.userId == uid })
        try context.delete(model: CachedBookState.self,
                           where: #Predicate<CachedBookState> { $0.userId == uid })
        try context.delete(model: CachedQuizState.self,
                           where: #Predicate<CachedQuizState> { $0.userId == uid })
        try context.delete(model: CachedNotebookEntry.self,
                           where: #Predicate<CachedNotebookEntry> { $0.userId == uid })
        try context.delete(model: CachedHighlight.self,
                           where: #Predicate<CachedHighlight> { $0.userId == uid })
        try context.delete(model: CachedReviewCard.self,
                           where: #Predicate<CachedReviewCard> { $0.userId == uid })
        try context.delete(model: PendingMutation.self,
                           where: #Predicate<PendingMutation> { $0.userId == uid })
        try context.save()
    }
}

// MARK: - BackgroundStore extension

extension BackgroundStore {
    /// Deletes all offline-schema rows for `userId` on the background actor.
    public func wipeUserData(userId: String) throws {
        let uid = userId
        try modelContext.delete(model: CachedBook.self,
                                where: #Predicate<CachedBook> { $0.userId == uid })
        try modelContext.delete(model: CachedChapter.self,
                                where: #Predicate<CachedChapter> { $0.userId == uid })
        try modelContext.delete(model: CachedManifest.self,
                                where: #Predicate<CachedManifest> { $0.userId == uid })
        try modelContext.delete(model: CachedProgress.self,
                                where: #Predicate<CachedProgress> { $0.userId == uid })
        try modelContext.delete(model: CachedBookState.self,
                                where: #Predicate<CachedBookState> { $0.userId == uid })
        try modelContext.delete(model: CachedQuizState.self,
                                where: #Predicate<CachedQuizState> { $0.userId == uid })
        try modelContext.delete(model: CachedNotebookEntry.self,
                                where: #Predicate<CachedNotebookEntry> { $0.userId == uid })
        try modelContext.delete(model: CachedHighlight.self,
                                where: #Predicate<CachedHighlight> { $0.userId == uid })
        try modelContext.delete(model: CachedReviewCard.self,
                                where: #Predicate<CachedReviewCard> { $0.userId == uid })
        try modelContext.delete(model: PendingMutation.self,
                                where: #Predicate<PendingMutation> { $0.userId == uid })
        try modelContext.save()
    }
}
