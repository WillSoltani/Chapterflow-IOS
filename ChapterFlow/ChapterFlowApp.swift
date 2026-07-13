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

    /// Configuration validation and live-graph creation are resolved exactly
    /// once, before SwiftUI can construct the root view.
    private let bootstrap: AppBootstrap

    init() {
        #if DEBUG
        // Apply XCUITest stub-server and auth-bypass overrides before any
        // configuration selection or AppFeature initialisation touches services.
        CFAppLaunchSupport.applyUITestOverrides()
        let config = CFAppLaunchSupport.resolveConfiguration(
            default: AppConfig.fromInfoPlist()
        )
        bootstrap = AppBootstrap(config: config, buildConfiguration: .debug)
        #else
        bootstrap = AppBootstrap(
            config: AppConfig.fromInfoPlist(),
            buildConfiguration: .nonDebug
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ConfiguredAppRootView(bootstrap: bootstrap)
        }
    }
}
