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
        // Control Center / Lock Screen / Action Button controls (P8.9)
        StartReadingControl()
        StartReviewControl()
        AudioPlaybackControl()
    }
}
