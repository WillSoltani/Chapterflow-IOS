import Foundation
import CoreKit
import Models

// MARK: - Handoff (NSUserActivity)

extension AppModel {

    /// Resumes a reading session received via Continuity Handoff.
    ///
    /// Called from `AppRootView.onContinueUserActivity` for both
    /// the custom `com.chapterflow.ios.reading` activity type (iOS → iOS)
    /// and `NSUserActivityTypeBrowsingWeb` (web → iOS via `webpageURL`).
    ///
    /// The `variantFamily` is read from the activity's `userInfo`; if absent
    /// the reader defaults to `.emh` which is a safe fallback for any book.
    public func handleHandoff(bookId: String, chapterNumber: Int, variantFamilyRaw: String?) {
        let family = variantFamilyRaw.map(VariantFamily.init(rawValue:)) ?? .emh
        pendingHandoffFlow = ReadingFlow(
            bookId: bookId,
            chapterNumber: chapterNumber,
            variantFamily: family
        )
    }
}
