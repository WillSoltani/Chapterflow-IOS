// Render-guard snapshot tests for the Reader screen.
//
// Deterministic & hermetic: renders the real screen off-screen with
// `ImageRenderer` (fed by `FakeReaderRepository` — no network, no live clock)
// and asserts a non-empty bitmap. No reference image is committed, so it can't
// flake across renderer versions / CI hosts while still catching layout traps,
// force-unwrap crashes and infinite-layout bugs across the light / dark /
// Dynamic-Type / device-size matrix. See docs/VISUAL-QA.md.

import SwiftUI
import Testing
import Models
import Persistence
@testable import ReaderFeature

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

// MARK: - Reader

@MainActor
@Suite("Reader — render guards")
struct ReaderRenderGuardTests {

    private func preferences(_ suite: String) -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: suite))
    }

    @Test("ReaderView renders across the matrix (loaded)")
    func loadedMatrix() {
        assertMatrix("Reader (loaded)") {
            ReaderView(readerModel: ReaderModel(
                bookId: "b-atomic-habits",
                chapterNumber: 1,
                variantFamily: .emh,
                repository: FakeReaderRepository(),
                preferences: preferences("cf.test.reader.loaded")
            ))
        }
    }

    @Test("ReaderView renders its offline / error state")
    func errorMatrix() {
        assertMatrix("Reader (error)") {
            ReaderView(readerModel: ReaderModel(
                bookId: "b-atomic-habits",
                chapterNumber: 1,
                variantFamily: .emh,
                repository: FakeReaderRepository(
                    chapterResponse: .failure(URLError(.notConnectedToInternet))
                ),
                preferences: preferences("cf.test.reader.error")
            ))
        }
    }
}
