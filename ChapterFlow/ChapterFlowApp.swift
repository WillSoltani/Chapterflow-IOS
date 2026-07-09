//
//  ChapterFlowApp.swift
//  ChapterFlow
//

import SwiftUI
import AppFeature
import CoreKit

@main
struct ChapterFlowApp: App {
    /// Bridges APNs `UIApplicationDelegate` callbacks into `NotificationsFeature`.
    /// The adaptor is a public type defined in `AppFeature` to avoid importing
    /// `NotificationsFeature` directly from the thin app shell.
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    /// App configuration read once at launch from Info.plist (backed by Secrets.xcconfig).
    private let appConfig = AppConfig.fromInfoPlist()

    init() {
        #if DEBUG
        // Apply XCUITest stub-server and auth-bypass overrides before any
        // SwiftUI body or AppFeature initialisation touches the network.
        CFAppLaunchSupport.applyUITestOverrides()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(config: appConfig)
                .environment(\.appConfig, appConfig)
        }
    }
}
