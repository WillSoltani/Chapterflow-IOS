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

    /// Retains the single observable bootstrap coordinator for the process.
    @State private var bootstrap: AppBootstrapCoordinator

    init() {
        #if DEBUG
        // Apply XCUITest stub-server and auth-bypass overrides before any
        // configuration selection or AppFeature initialisation touches services.
        CFAppLaunchSupport.applyUITestOverrides()
        let config = CFAppLaunchSupport.resolveConfiguration(
            default: AppConfig.fromInfoPlist()
        )
        CFAppLaunchSupport.seedHermeticAccountPreferencesIfNeeded(config: config)
        _bootstrap = State(initialValue: CFAppLaunchSupport.makeBootstrap(
            config: config,
            buildConfiguration: .debug
        ))
        #else
        _bootstrap = State(initialValue: AppBootstrapCoordinator(
            config: AppConfig.fromInfoPlist(),
            buildConfiguration: .nonDebug
        ))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ConfiguredAppRootView(bootstrap: bootstrap)
        }
    }
}
