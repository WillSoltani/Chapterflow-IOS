/// DesignSystem snapshot / render tests.
///
/// ## Generating reference images
///
/// Run once with ``SNAPSHOT_RECORD=1`` to create (or refresh) the PNG references:
///
/// ```bash
/// SNAPSHOT_RECORD=1 swift test \
///   --package-path Packages/DesignSystem \
///   --filter "DesignSystemSnapshotTests"
/// ```
///
/// Commit the files written to ``Tests/DesignSystemSnapshotTests/__Snapshots__/``.
///
/// ## CI behaviour
///
/// Without ``SNAPSHOT_RECORD``, each test loads the committed reference and
/// compares it against a freshly rendered image (1 % pixel-difference tolerance).
/// Tests fail on visual regressions.

import Testing
import SwiftUI
@testable import DesignSystem

@Suite("DesignSystem Snapshots")
struct DesignSystemSnapshotTests {

    // ── Standard viewport (iPhone 15 Pro) ─────────────────────────────────────
    private let viewport = CGSize(width: 393, height: 2400)
    private let tallViewport = CGSize(width: 393, height: 5000)

    // MARK: - Light mode

    @Test("Gallery renders in light mode")
    @MainActor
    func galleryLight() throws {
        let view = DesignSystemGallery()
            .environment(\.colorScheme, .light)
        try assertSnapshot(view, named: "gallery-light", size: viewport)
    }

    // MARK: - Dark mode

    @Test("Gallery renders in dark mode")
    @MainActor
    func galleryDark() throws {
        let view = DesignSystemGallery()
            .environment(\.colorScheme, .dark)
        try assertSnapshot(view, named: "gallery-dark", size: viewport)
    }

    // MARK: - Accessibility XXL text

    @Test("Gallery renders with XXL dynamic type (accessibility5)")
    @MainActor
    func galleryXXL() throws {
        let view = DesignSystemGallery()
            .environment(\.dynamicTypeSize, .accessibility5)
        try assertSnapshot(view, named: "gallery-xxl", size: tallViewport)
    }

    // MARK: - Component-level render guards
    // These verify individual components render without crashing,
    // independently of the full gallery.

    @Test("CFProgressRing renders across progress range")
    @MainActor
    func progressRingStates() throws {
        let view = HStack(spacing: 16) {
            CFProgressRing(progress: 0.0)
                .frame(width: 60, height: 60)
            CFProgressRing(progress: 0.5)
                .frame(width: 60, height: 60)
            CFProgressRing(progress: 1.0)
                .frame(width: 60, height: 60)
        }
        .padding()
        .background(Color.cfBackground)
        try assertSnapshot(
            view,
            named: "progress-ring-states",
            size: CGSize(width: 260, height: 100)
        )
    }

    @Test("CFSkeleton renders without crashing")
    @MainActor
    func skeletonRenders() throws {
        let view = VStack(spacing: 8) {
            CFSkeleton()
                .frame(width: 200, height: 16)
            CFSkeleton()
                .frame(width: 140, height: 16)
            CFSkeleton()
                .frame(width: 160, height: 16)
        }
        .padding()
        .background(Color.cfBackground)
        try assertSnapshot(
            view,
            named: "skeleton",
            size: CGSize(width: 260, height: 120)
        )
    }

    @Test("CFEmptyState renders without crashing")
    @MainActor
    func emptyStateRenders() throws {
        let view = CFEmptyState(
            systemImage: "book.closed",
            title: "Nothing here yet",
            description: "Your library is empty."
        )
        .frame(width: 393)
        .background(Color.cfBackground)
        try assertSnapshot(
            view,
            named: "empty-state",
            size: CGSize(width: 393, height: 300)
        )
    }
}
