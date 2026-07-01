//
//  ChapterFlowApp.swift
//  ChapterFlow
//

import SwiftUI
import AppFeature

@main
struct ChapterFlowApp: App {
    var body: some Scene {
        WindowGroup {
            // AppFeature is the composition root; it owns the tab shell.
            AppRootView()
        }
    }
}
