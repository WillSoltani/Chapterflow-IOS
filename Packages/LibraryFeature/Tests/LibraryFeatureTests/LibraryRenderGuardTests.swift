// Render-guard snapshot tests for the Library screen.
//
// These are DETERMINISTIC and HERMETIC by construction: each test renders the
// real screen off-screen with `ImageRenderer` (fed by in-package preview fakes
// — no network, no live clock) and asserts a non-empty bitmap is produced.
// They commit NO reference image, so they cannot drift / flake across renderer
// versions or CI hosts, yet they still catch layout traps, force-unwrap
// crashes and infinite-layout bugs across the light / dark / Dynamic-Type /
// device-size matrix. See docs/VISUAL-QA.md for the full matrix rationale.

import SwiftUI
import Testing
import Persistence
@testable import LibraryFeature

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

/// Device viewports spanning smallest iPhone SE → iPad portrait.
private enum RenderDevice {
    static let se = CGSize(width: 320, height: 568)      // iPhone SE (smallest)
    static let phone = CGSize(width: 393, height: 852)   // iPhone 16 Pro
    static let proMax = CGSize(width: 440, height: 956)  // iPhone 16 Pro Max
    static let ipad = CGSize(width: 834, height: 1112)   // iPad portrait
}

/// Renders one screen across the full visual-QA matrix.
@MainActor
private func assertMatrix<V: View>(_ name: String, _ make: () -> V) {
    assertRenders(make().environment(\.colorScheme, .light), "\(name) — light")
    assertRenders(make().environment(\.colorScheme, .dark), "\(name) — dark")
    assertRenders(make().environment(\.dynamicTypeSize, .xSmall), "\(name) — XS type")
    assertRenders(make().environment(\.dynamicTypeSize, .accessibility5), "\(name) — AX5 type")
    assertRenders(make(), "\(name) — iPhone SE", size: RenderDevice.se)
    assertRenders(make(), "\(name) — Pro Max", size: RenderDevice.proMax)
    assertRenders(make(), "\(name) — iPad", size: RenderDevice.ipad)
    assertRenders(
        make().environment(\.layoutDirection, .rightToLeft),
        "\(name) — RTL"
    )
}

// MARK: - Library

@MainActor
@Suite("Library — render guards")
struct LibraryRenderGuardTests {

    @Test("LibraryView renders across the matrix (loaded)")
    func loadedMatrix() {
        assertMatrix("Library (loaded)") {
            LibraryView(
                repository: PreviewData.loadedRepo,
                bookDetailRepository: PreviewData.bookDetailInProgress,
                preferences: AppPreferences(keyPrefix: "test.library-render."),
                store: KeyValueStore(keyPrefix: "test.library-render.")
            )
        }
    }

    @Test("LibraryView renders with a free-locked book-detail repository")
    func freeLockedMatrix() {
        assertMatrix("Library (free-locked)") {
            LibraryView(
                repository: PreviewData.loadedRepo,
                bookDetailRepository: PreviewData.bookDetailFreeLocked,
                preferences: AppPreferences(keyPrefix: "test.library-render."),
                store: KeyValueStore(keyPrefix: "test.library-render.")
            )
        }
    }

    @Test("BookDetailView keeps metadata visible when private state is unavailable")
    func bookDetailPrivateFailureMatrix() async {
        let model = BookDetailModel(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailStateUnavailable
        )
        await model.fetch()

        assertMatrix("Book Detail (private state unavailable)") {
            NavigationStack {
                BookDetailView(model: model)
            }
        }
    }

    @Test("BookDetailView renders compatibility-unknown state across the matrix")
    func bookDetailCompatibilityMatrix() async {
        let model = BookDetailModel(
            bookId: "b-atomic-habits",
            repository: PreviewData.bookDetailCompatibilityUnknown
        )
        await model.fetch()

        assertMatrix("Book Detail (compatibility unknown)") {
            NavigationStack {
                BookDetailView(model: model)
            }
        }
    }
}
