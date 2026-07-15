import WidgetKit
import SwiftUI

@main
struct ChapterflowWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Home-screen & Lock Screen widgets (P8.1)
        StreakWidget()
        ContinueReadingWidget()
        ProgressRingWidget()
        NextReviewWidget()
        // Live Activities (P8.2)
        ReadingSessionActivity()
        StreakAtRiskActivity()
        // P8.9 controls remain unregistered until WP-ID-01B can bind their
        // App Group commands and presentation state to a proven account.
    }
}
