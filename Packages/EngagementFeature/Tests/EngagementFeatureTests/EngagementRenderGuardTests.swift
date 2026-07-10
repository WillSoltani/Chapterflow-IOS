// Render-guard snapshot tests for the Engagement dashboard screen.
//
// Deterministic & hermetic: renders the real screen off-screen with
// `ImageRenderer` (fed by `EngagementRepository.preview` — no network, no live
// clock) and asserts a non-empty bitmap. No reference image is committed, so it
// can't flake across renderer versions / CI hosts while still catching layout
// traps and crashes across the light / dark / Dynamic-Type / device-size
// matrix. See docs/VISUAL-QA.md.
//
// ⚠️ Main-actor cooperation. `ImageRenderer` renders synchronously on the main
// actor. This bundle also contains many async `@MainActor` model tests that
// `load()` then wait a fixed interval before asserting. If a full matrix pass
// held the main actor in one greedy default-priority block it would starve
// those model tests inside their wait window and they'd observe un-settled
// state (the same shared-resource contention that produced the debounce /
// AVPlayer flakes). To stay a good citizen of the parallel bundle each render
// runs on a **`.background`-priority** main-actor task that we `await`: the
// suite yields the main actor between renders and the scheduler always prefers
// the model tests' default-priority work at every boundary, so their loads
// finish on time. The suite is also `.serialized` so its own renders never pile
// up on each other.

import SwiftUI
import Testing
@testable import EngagementFeature

// MARK: - Shared render-guard harness

/// Renders `view` off-screen on a background-priority main-actor task and
/// asserts a bitmap is produced. Running at `.background` priority guarantees
/// the scheduler prefers any ready default-priority work (the async model
/// tests) whenever they compete for the main actor.
@MainActor
private func assertRenders(
    _ view: some View,
    _ label: Comment,
    size: CGSize = RenderDevice.phone
) async {
    let rendered = await Task(priority: .background) { @MainActor in
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
#if canImport(AppKit)
        return renderer.nsImage != nil
#else
        return renderer.uiImage != nil
#endif
    }.value
    #expect(rendered, label)
}

private enum RenderDevice {
    static let se = CGSize(width: 320, height: 568)
    static let phone = CGSize(width: 393, height: 852)
    static let proMax = CGSize(width: 440, height: 956)
    static let ipad = CGSize(width: 834, height: 1112)
}

@MainActor
private func assertMatrix<V: View>(_ name: String, _ make: () -> V) async {
    let cells: [(String, AnyView)] = [
        ("light", AnyView(make().environment(\.colorScheme, .light))),
        ("dark", AnyView(make().environment(\.colorScheme, .dark))),
        ("XS type", AnyView(make().environment(\.dynamicTypeSize, .xSmall))),
        ("AX5 type", AnyView(make().environment(\.dynamicTypeSize, .accessibility5))),
        ("iPhone SE", AnyView(make())),
        ("Pro Max", AnyView(make())),
        ("iPad", AnyView(make())),
        ("RTL", AnyView(make().environment(\.layoutDirection, .rightToLeft)))
    ]
    let sizes: [String: CGSize] = [
        "iPhone SE": RenderDevice.se, "Pro Max": RenderDevice.proMax, "iPad": RenderDevice.ipad
    ]
    for (variant, view) in cells {
        // Hand the main actor back between renders so any co-scheduled model
        // test's async `load()` gets a guaranteed window to settle.
        try? await Task.sleep(for: .milliseconds(2))
        await assertRenders(view, "\(name) — \(variant)", size: sizes[variant] ?? RenderDevice.phone)
    }
}

// MARK: - Dashboard

@MainActor
@Suite("Engagement — render guards", .serialized)
struct EngagementRenderGuardTests {

    @Test("DashboardView renders across the matrix (loaded)")
    func loadedMatrix() async {
        await assertMatrix("Dashboard (loaded)") {
            NavigationStack {
                DashboardView(model: DashboardModel(repository: .preview))
            }
        }
    }
}
