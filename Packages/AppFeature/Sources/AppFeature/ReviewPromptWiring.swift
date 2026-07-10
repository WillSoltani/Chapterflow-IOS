import SwiftUI
import StoreKit
import CoreKit
import Persistence

/// A ``ReviewPromptVersionStore`` backed by the app's existing ``KeyValueStore``
/// (App Group `UserDefaults`), so the last-prompted version survives launches without a
/// new singleton or bespoke storage.
///
/// `@unchecked Sendable`: the only stored dependency is `KeyValueStore`, which wraps a
/// thread-safe `UserDefaults`; access is confined to reading/writing a single string key.
struct KeyValueReviewPromptVersionStore: ReviewPromptVersionStore, @unchecked Sendable {
    private static let key = "review.lastPromptedVersion"
    private let store: KeyValueStore

    init(store: KeyValueStore = KeyValueStore()) {
        self.store = store
    }

    func lastPromptedVersion() -> String? {
        store.value(String.self, forKey: Self.key)
    }

    func setLastPromptedVersion(_ version: String) {
        try? store.set(version, forKey: Self.key)
    }
}

extension Bundle {
    /// The app's marketing version (`CFBundleShortVersionString`), or an empty string if
    /// unavailable — which ``ReviewPromptPolicy`` treats as "never prompt".
    var appShortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

// MARK: - Trigger call site helper

/// Considers an App Store review request after a genuinely positive moment: passing a
/// chapter quiz. Delegates the decision to `controller` (once-per-version, streak-gated)
/// and only asks StoreKit when the policy allows. The reading streak is read from the
/// shared app-state snapshot the app already maintains for widgets.
@MainActor
func requestReviewAfterQuizPass(_ model: AppModel, _ requestReview: RequestReviewAction) {
    #if DEBUG
    // Never let the system review sheet appear during stubbed UI-test runs, where it would
    // overlay the app and block automation (mirrors ReachabilityService's UI-test guard).
    if ProcessInfo.processInfo.environment["CF_STUB_SERVER"] == "1" { return }
    #endif

    let streakDays = SharedStateReader().load().streakDays
    model.reviewPromptController.requestReviewIfAppropriate(
        for: .quizCompleted(passed: true, currentStreakDays: streakDays)
    ) {
        // Decouple from the tap and give the pass animation a beat to settle before the
        // system sheet appears, per Apple's ratings-and-reviews guidance.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            requestReview()
        }
    }
}
