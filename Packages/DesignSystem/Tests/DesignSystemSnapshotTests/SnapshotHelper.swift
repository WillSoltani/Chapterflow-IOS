// SnapshotHelper — lightweight snapshot testing utility.
// Uses SwiftUI's ImageRenderer (macOS 14+) with no external dependencies.
// Reference images live in __Snapshots__/ next to this source file
// and are committed to git.

import SwiftUI
import Testing

// MARK: - Record mode

/// When `SNAPSHOT_RECORD=1` is set the test writes (or overwrites) the
/// reference image instead of comparing.  Use this to generate references
/// for the first time or after intentional design changes:
///
///   SNAPSHOT_RECORD=1 swift test --package-path Packages/DesignSystem \
///     --filter "DesignSystemSnapshotTests"
var isSnapshotRecordMode: Bool {
    ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
}

// MARK: - Error

enum SnapshotError: Error, CustomStringConvertible {
    case renderFailed(String)
    case missingReference(String)
    case mismatch(name: String, diffRatio: Double, failurePath: String)

    var description: String {
        switch self {
        case .renderFailed(let n):
            return "ImageRenderer produced no image for '\(n)'"
        case .missingReference(let n):
            return "No committed reference for '\(n)'. Run with SNAPSHOT_RECORD=1 to create it."
        case .mismatch(let n, let r, let p):
            let pct = String(format: "%.2f", r * 100)
            return "'\(n)' differs (\(pct)% pixels changed). Failure image: \(p)"
        }
    }
}

// MARK: - Core assertion

/// Renders `view` at `size` points (@`scale`×) and either records or compares.
///
/// - Parameters:
///   - view:      The SwiftUI view to render.
///   - named:     Stable file name for the snapshot (no extension).
///   - size:      Render size in points (default: 393 × 852, iPhone 15 Pro).
///   - scale:     Pixel-density multiplier (default 2.0 = @2x).
///   - tolerance: Fraction of pixels allowed to differ (default 1 % = 0.01).
///   - file:      Source file path; used to locate the __Snapshots__ directory.
@MainActor
func assertSnapshot<V: View>(
    _ view: V,
    named name: String,
    size: CGSize = CGSize(width: 393, height: 852),
    scale: CGFloat = 2.0,
    tolerance: Double = 0.01,
    file: String = #filePath
) throws {
#if canImport(AppKit)
    let renderer = ImageRenderer(
        content: view.frame(width: size.width, height: size.height)
    )
    renderer.scale = scale

    guard
        let nsImage = renderer.nsImage,
        let tiff    = nsImage.tiffRepresentation,
        let rep     = NSBitmapImageRep(data: tiff),
        let png     = rep.representation(using: .png, properties: [:])
    else {
        throw SnapshotError.renderFailed(name)
    }

    let dir    = snapshotDir(file: file)
    let refURL = dir.appendingPathComponent("\(name).png")

    if isSnapshotRecordMode {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: refURL)
        // Record mode: writing succeeds → test passes.
        return
    }

    guard FileManager.default.fileExists(atPath: refURL.path) else {
        throw SnapshotError.missingReference(name)
    }

    guard let refPNG = try? Data(contentsOf: refURL) else {
        throw SnapshotError.missingReference(name)
    }

    if png == refPNG { return } // byte-identical fast path

    let diff = pixelMismatch(new: png, ref: refPNG)
    guard diff > tolerance else { return }

    let failURL = dir.appendingPathComponent("\(name)-FAIL.png")
    try? png.write(to: failURL)
    throw SnapshotError.mismatch(name: name, diffRatio: diff, failurePath: failURL.path)

#else
    // UIKit-only targets (iOS simulator): skip pixel comparison.
    // The gallery render tests below still verify crash-free rendering.
    _ = view; _ = name; _ = size; _ = scale; _ = tolerance
#endif
}

// MARK: - Snapshot directory

/// Returns the `__Snapshots__` directory located next to the test source file.
/// `#filePath` expands to the absolute source path at compile time, giving a
/// stable location on any machine where the repo is checked out.
private func snapshotDir(file: String) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")
}

// MARK: - Pixel comparison (AppKit only)

#if canImport(AppKit)
import AppKit

private func pixelMismatch(new newPNG: Data, ref refPNG: Data) -> Double {
    guard
        let newImg = NSImage(data: newPNG),
        let refImg = NSImage(data: refPNG),
        let newRep = NSBitmapImageRep(data: newImg.tiffRepresentation ?? Data()),
        let refRep = NSBitmapImageRep(data: refImg.tiffRepresentation ?? Data())
    else { return 1.0 }

    guard
        newRep.pixelsWide == refRep.pixelsWide,
        newRep.pixelsHigh == refRep.pixelsHigh
    else { return 1.0 }

    let w = newRep.pixelsWide
    let h = newRep.pixelsHigh
    guard w > 0, h > 0 else { return 1.0 }

    var diff = 0
    for x in 0 ..< w {
        for y in 0 ..< h {
            let nc = newRep.colorAt(x: x, y: y) ?? .clear
            let rc = refRep.colorAt(x: x, y: y) ?? .clear
            let delta = abs(nc.redComponent   - rc.redComponent)
                      + abs(nc.greenComponent - rc.greenComponent)
                      + abs(nc.blueComponent  - rc.blueComponent)
            if delta > 0.05 { diff += 1 }
        }
    }
    return Double(diff) / Double(w * h)
}
#endif
