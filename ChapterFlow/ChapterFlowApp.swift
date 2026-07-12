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

    /// Evaluated once before the application service graph can be constructed.
    private let configurationState: AppConfigurationState

    init() {
        #if DEBUG
        // Apply XCUITest stub-server and auth-bypass overrides before any
        // SwiftUI body or AppFeature initialisation touches the network.
        CFAppLaunchSupport.applyUITestOverrides()
        let appConfig = CFAppLaunchSupport.configurationOverride ?? AppConfig.fromInfoPlist()
        #else
        let appConfig = AppConfig.fromInfoPlist()
        #endif
        configurationState = appConfig.validate()
    }

    var body: some Scene {
        WindowGroup {
            ConfiguredAppRootView(state: configurationState)
        }
    }
}
