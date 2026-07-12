import Foundation
import SwiftUI
import Testing

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import QuartzCore
import UIKit
#endif

enum ReferenceSnapshotError: Error, CustomStringConvertible {
    case renderFailed(String)
    case recordModeForbiddenInCI
    case missingReference(String)
    case mismatch(name: String, diffRatio: Double, failurePath: String)
    case unsupportedPlatform

    var description: String {
        switch self {
        case .renderFailed(let name):
            return "The platform snapshot renderer produced no image for '\(name)'"
        case .recordModeForbiddenInCI:
            return "Snapshot record mode is forbidden when CI=true."
        case .missingReference(let name):
            return "No committed reference for '\(name)'. Run with SNAPSHOT_RECORD=1 to create it."
        case .mismatch(let name, let diffRatio, let failurePath):
            let percent = String(format: "%.2f", diffRatio * 100)
            return "'\(name)' differs (\(percent)% pixels changed). Failure image: \(failurePath)"
        case .unsupportedPlatform:
            return "Reference snapshots require AppKit or UIKit; this platform is unsupported."
        }
    }
}

enum SnapshotScrollPosition: Equatable {
    case top
    case bottom
}

/// Test-target-local adaptation of DesignSystem's lightweight snapshot helper.
@MainActor
func assertReferenceSnapshot<ViewUnderTest: View>(
    _ view: ViewUnderTest,
    named name: String,
    size: CGSize,
    scale: CGFloat = 2,
    tolerance: Double = 0.001,
    scrollPosition: SnapshotScrollPosition = .top,
    file: String = #filePath
) throws {
#if canImport(AppKit) || canImport(UIKit)
    let shouldRecord = isSnapshotRecordMode
    if shouldRecord && isContinuousIntegration {
        throw ReferenceSnapshotError.recordModeForbiddenInCI
    }
    let referenceName = "\(name)-\(snapshotPlatformName)"
    let png = try renderedPNG(
        view,
        named: referenceName,
        size: size,
        scale: scale,
        scrollPosition: scrollPosition
    )
    guard imageHasVisualVariation(png) else {
        throw ReferenceSnapshotError.renderFailed(referenceName)
    }
    let sourceDirectory = referenceDirectory(file: file)
    let sourceReferenceURL = sourceDirectory.appendingPathComponent("\(referenceName).png")

    if shouldRecord {
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try png.write(to: sourceReferenceURL)
        return
    }

    guard let referenceURL = bundledReferenceURL(named: referenceName),
          let referencePNG = try? Data(contentsOf: referenceURL) else {
        throw ReferenceSnapshotError.missingReference(referenceName)
    }
    if png == referencePNG {
        return
    }

    let diffRatio = pixelMismatch(new: png, reference: referencePNG)
    guard diffRatio > tolerance else {
        return
    }

    let failureURL = writeFailureImage(
        png,
        named: referenceName,
        preferredDirectory: sourceDirectory
    )
    throw ReferenceSnapshotError.mismatch(
        name: referenceName,
        diffRatio: diffRatio,
        failurePath: failureURL.path
    )
#else
    throw ReferenceSnapshotError.unsupportedPlatform
#endif
}

private var isSnapshotRecordMode: Bool {
#if SNAPSHOT_RECORD
    true
#else
    ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
#endif
}

private var isContinuousIntegration: Bool {
    ProcessInfo.processInfo.environment["CI"]?.lowercased() == "true"
}

private var snapshotPlatformName: String {
#if canImport(AppKit)
    "macos"
#elseif canImport(UIKit)
    "ios"
#else
    "unsupported"
#endif
}

private func referenceDirectory(file: String) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")
}

private func bundledReferenceURL(named name: String) -> URL? {
    Bundle.module.url(
        forResource: name,
        withExtension: "png",
        subdirectory: "__Snapshots__"
    )
}

private func writeFailureImage(
    _ png: Data,
    named name: String,
    preferredDirectory: URL
) -> URL {
    let preferredURL = preferredDirectory.appendingPathComponent("\(name)-FAIL.png")
    do {
        try png.write(to: preferredURL)
        return preferredURL
    } catch {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-FAIL.png")
        try? png.write(to: temporaryURL)
        return temporaryURL
    }
}

#if canImport(AppKit)
@MainActor
private func renderedPNG<ViewUnderTest: View>(
    _ view: ViewUnderTest,
    named name: String,
    size: CGSize,
    scale: CGFloat,
    scrollPosition: SnapshotScrollPosition
) throws -> Data {
    _ = scrollPosition
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: .aqua)
    host.wantsLayer = true
    host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    host.layoutSubtreeIfNeeded()

    let pixelWidth = Int(size.width * scale)
    let pixelHeight = Int(size.height * scale)
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw ReferenceSnapshotError.renderFailed(name)
    }
    representation.size = size
    host.cacheDisplay(in: host.bounds, to: representation)

    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw ReferenceSnapshotError.renderFailed(name)
    }
    return png
}

private func pixelMismatch(new newPNG: Data, reference referencePNG: Data) -> Double {
    guard let newImage = NSImage(data: newPNG),
          let referenceImage = NSImage(data: referencePNG),
          let newRepresentation = NSBitmapImageRep(data: newImage.tiffRepresentation ?? Data()),
          let referenceRepresentation = NSBitmapImageRep(
              data: referenceImage.tiffRepresentation ?? Data()
          ),
          newRepresentation.pixelsWide == referenceRepresentation.pixelsWide,
          newRepresentation.pixelsHigh == referenceRepresentation.pixelsHigh else {
        return 1
    }

    let width = newRepresentation.pixelsWide
    let height = newRepresentation.pixelsHigh
    guard width > 0, height > 0 else {
        return 1
    }

    var differingPixels = 0
    for xCoordinate in 0 ..< width {
        for yCoordinate in 0 ..< height {
            let newColor = newRepresentation.colorAt(x: xCoordinate, y: yCoordinate) ?? .clear
            let referenceColor = referenceRepresentation.colorAt(
                x: xCoordinate,
                y: yCoordinate
            ) ?? .clear
            let delta = abs(newColor.redComponent - referenceColor.redComponent)
                + abs(newColor.greenComponent - referenceColor.greenComponent)
                + abs(newColor.blueComponent - referenceColor.blueComponent)
                + abs(newColor.alphaComponent - referenceColor.alphaComponent)
            if delta > 0.05 {
                differingPixels += 1
            }
        }
    }
    return Double(differingPixels) / Double(width * height)
}

private func imageHasVisualVariation(_ png: Data) -> Bool {
    guard let image = NSImage(data: png),
          let representation = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
          representation.pixelsWide > 0,
          representation.pixelsHigh > 0,
          let baseline = representation.colorAt(x: 0, y: 0) else {
        return false
    }

    for xCoordinate in stride(from: 0, to: representation.pixelsWide, by: 4) {
        for yCoordinate in stride(from: 0, to: representation.pixelsHigh, by: 4) {
            guard let color = representation.colorAt(x: xCoordinate, y: yCoordinate) else {
                continue
            }
            let delta = abs(color.redComponent - baseline.redComponent)
                + abs(color.greenComponent - baseline.greenComponent)
                + abs(color.blueComponent - baseline.blueComponent)
                + abs(color.alphaComponent - baseline.alphaComponent)
            if delta > 0.05 {
                return true
            }
        }
    }
    return false
}
#elseif canImport(UIKit)
private struct SnapshotPixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int
}

@MainActor
private func renderedPNG<ViewUnderTest: View>(
    _ view: ViewUnderTest,
    named name: String,
    size: CGSize,
    scale: CGFloat,
    scrollPosition: SnapshotScrollPosition
) throws -> Data {
    let host = UIHostingController(
        rootView: view.frame(width: size.width, height: size.height)
    )
    host.overrideUserInterfaceStyle = .light
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.overrideUserInterfaceStyle = .light
    window.backgroundColor = .systemBackground
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host.view.frame = window.bounds
    host.view.backgroundColor = .systemBackground
    settleSnapshotHierarchy(window: window, hostView: host.view)

    if scrollPosition == .bottom {
        guard let scrollView = firstVerticallyScrollableView(in: host.view) else {
            throw ReferenceSnapshotError.renderFailed(name)
        }
        let maximumOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        UIView.performWithoutAnimation {
            scrollView.setContentOffset(CGPoint(x: 0, y: maximumOffset), animated: false)
            scrollView.layoutIfNeeded()
        }
        settleSnapshotHierarchy(window: window, hostView: host.view)
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { context in
        host.view.layer.render(in: context.cgContext)
    }
    guard let png = image.pngData() else {
        throw ReferenceSnapshotError.renderFailed(name)
    }
    return png
}

/// Gives SwiftUI-backed UIKit views a bounded opportunity to complete their
/// first display pass. SF Symbols are resolved during that pass and can be
/// omitted by a synchronous `CALayer.render(in:)` taken immediately after layout.
@MainActor
private func settleSnapshotHierarchy(window: UIWindow, hostView: UIView) {
    for _ in 0 ..< 3 {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    window.layoutIfNeeded()
    hostView.layoutIfNeeded()
    CATransaction.flush()
}

@MainActor
private func firstVerticallyScrollableView(in view: UIView) -> UIScrollView? {
    if let scrollView = view as? UIScrollView,
       scrollView.contentSize.height > scrollView.bounds.height + 1 {
        return scrollView
    }
    for subview in view.subviews {
        if let match = firstVerticallyScrollableView(in: subview) {
            return match
        }
    }
    return nil
}

private func pixelMismatch(new newPNG: Data, reference referencePNG: Data) -> Double {
    guard let newPixels = rgbaPixels(from: newPNG),
          let referencePixels = rgbaPixels(from: referencePNG),
          newPixels.width == referencePixels.width,
          newPixels.height == referencePixels.height else {
        return 1
    }

    var differingPixels = 0
    for offset in stride(from: 0, to: newPixels.bytes.count, by: 4) {
        let redDelta = abs(Int(newPixels.bytes[offset]) - Int(referencePixels.bytes[offset]))
        let greenDelta = abs(
            Int(newPixels.bytes[offset + 1]) - Int(referencePixels.bytes[offset + 1])
        )
        let blueDelta = abs(
            Int(newPixels.bytes[offset + 2]) - Int(referencePixels.bytes[offset + 2])
        )
        let alphaDelta = abs(
            Int(newPixels.bytes[offset + 3]) - Int(referencePixels.bytes[offset + 3])
        )
        if redDelta + greenDelta + blueDelta + alphaDelta > 13 {
            differingPixels += 1
        }
    }

    let pixelCount = newPixels.width * newPixels.height
    guard pixelCount > 0 else {
        return 1
    }
    return Double(differingPixels) / Double(pixelCount)
}

private func imageHasVisualVariation(_ png: Data) -> Bool {
    guard let pixels = rgbaPixels(from: png),
          let baselineRed = pixels.bytes.first,
          pixels.bytes.count >= 4 else {
        return false
    }
    let baselineGreen = pixels.bytes[1]
    let baselineBlue = pixels.bytes[2]
    let baselineAlpha = pixels.bytes[3]

    for offset in stride(from: 0, to: pixels.bytes.count, by: 16) {
        let redDelta = abs(Int(pixels.bytes[offset]) - Int(baselineRed))
        let greenDelta = abs(Int(pixels.bytes[offset + 1]) - Int(baselineGreen))
        let blueDelta = abs(Int(pixels.bytes[offset + 2]) - Int(baselineBlue))
        let alphaDelta = abs(Int(pixels.bytes[offset + 3]) - Int(baselineAlpha))
        if redDelta + greenDelta + blueDelta + alphaDelta > 13 {
            return true
        }
    }
    return false
}

private func rgbaPixels(from png: Data) -> SnapshotPixels? {
    guard let image = UIImage(data: png),
          let source = image.cgImage else {
        return nil
    }

    let width = source.width
    let height = source.height
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let baseAddress = buffer.baseAddress,
              let context = CGContext(
                  data: baseAddress,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return false
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard didDraw else {
        return nil
    }
    return SnapshotPixels(bytes: bytes, width: width, height: height)
}
#endif
