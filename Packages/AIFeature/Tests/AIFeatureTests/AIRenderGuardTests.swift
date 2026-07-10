// Render-guard snapshot tests for the "Ask the Book" AI screen.
//
// Deterministic & hermetic: renders the real screen off-screen with
// `ImageRenderer` (fed by `FakeAIRepository` — no network, no live clock) and
// asserts a non-empty bitmap. No reference image is committed, so it can't flake
// across renderer versions / CI hosts while still catching layout traps and
// crashes across the light / dark / Dynamic-Type / device-size matrix.
// See docs/VISUAL-QA.md.

import SwiftUI
import Testing
@testable import AIFeature

// MARK: - Shared render-guard harness

@MainActor
private func assertRenders(
    _ view: some View,
    _ label: Comment,
    size: CGSize = RenderDevice.phone
) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
#if canImport(AppKit)
    #expect(renderer.nsImage != nil, label)
#else
    #expect(renderer.uiImage != nil, label)
#endif
}

private enum RenderDevice {
    static let se = CGSize(width: 320, height: 568)
    static let phone = CGSize(width: 393, height: 852)
    static let proMax = CGSize(width: 440, height: 956)
    static let ipad = CGSize(width: 834, height: 1112)
}

@MainActor
private func assertMatrix<V: View>(_ name: String, _ make: () -> V) {
    assertRenders(make().environment(\.colorScheme, .light), "\(name) — light")
    assertRenders(make().environment(\.colorScheme, .dark), "\(name) — dark")
    assertRenders(make().environment(\.dynamicTypeSize, .xSmall), "\(name) — XS type")
    assertRenders(make().environment(\.dynamicTypeSize, .accessibility5), "\(name) — AX5 type")
    assertRenders(make(), "\(name) — iPhone SE", size: RenderDevice.se)
    assertRenders(make(), "\(name) — Pro Max", size: RenderDevice.proMax)
    assertRenders(make(), "\(name) — iPad", size: RenderDevice.ipad)
    assertRenders(make().environment(\.layoutDirection, .rightToLeft), "\(name) — RTL")
}

// MARK: - Ask the Book

@MainActor
@Suite("AI Ask — render guards")
struct AIRenderGuardTests {

    private func model() -> AskTheBookModel {
        AskTheBookModel(
            bookId: "b-atomic-habits",
            userId: "preview-user",
            bookTitle: "Atomic Habits",
            repository: FakeAIRepository(delay: 0)
        )
    }

    @Test("AskTheBookSheet renders across the matrix (idle)")
    func idleMatrix() {
        assertMatrix("Ask (idle)") {
            AskTheBookSheet(model: model())
        }
    }

    @Test("AskTheBookSheet renders with a selection-context chip")
    func contextMatrix() {
        assertMatrix("Ask (context)") {
            AskTheBookSheet(model: AskTheBookModel(
                bookId: "b-atomic-habits",
                userId: "preview-user",
                bookTitle: "Atomic Habits",
                repository: FakeAIRepository(delay: 0),
                selectionContext: "Habits are the compound interest of self-improvement."
            ))
        }
    }
}
