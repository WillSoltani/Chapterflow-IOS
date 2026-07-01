//
//  ChapterFlowApp.swift
//  ChapterFlow
//

import SwiftUI
import AppFeature
import CoreKit

@main
struct ChapterFlowApp: App {
    /// App configuration read once at launch from Info.plist (backed by Secrets.xcconfig).
    private let appConfig = AppConfig.fromInfoPlist()

    var body: some Scene {
        WindowGroup {
            AppRootView(config: appConfig)
                .environment(\.appConfig, appConfig)
        }
    }
}
