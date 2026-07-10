import Foundation
import os

// MARK: - WhatsNewContentProvider

/// Loads bundled What's New content and selects the release to display.
///
/// Content lives in `Resources/WhatsNew.json` (bundled data, never hardcoded in
/// a view). Decoding is tolerant (RF2): a missing or corrupt file yields an
/// empty release list rather than a crash.
public struct WhatsNewContentProvider: Sendable {
    private let content: WhatsNewContent

    private static let logger = Logger(subsystem: "com.chapterflow.ios", category: "WhatsNew")

    /// Loads content from the given bundle (defaults to this module's bundle).
    public init(bundle: Bundle? = nil) {
        self.content = Self.loadContent(from: bundle ?? .module)
    }

    /// Injects pre-built content, for tests and previews.
    public init(content: WhatsNewContent) {
        self.content = content
    }

    /// All bundled releases.
    public var releases: [WhatsNewRelease] { content.releases }

    /// The release to show for `version`.
    ///
    /// Prefers an exact version match; otherwise falls back to the newest
    /// release that is not newer than `version`, so a build shipped ahead of its
    /// notes still shows the most relevant available content. Returns `nil` when
    /// there is no suitable release.
    public func release(forVersion version: String) -> WhatsNewRelease? {
        if let exact = content.releases.first(where: { $0.version == version }) {
            return exact
        }
        let target = AppVersion(version)
        return content.releases
            .filter { AppVersion($0.version) <= target }
            .max { AppVersion($0.version) < AppVersion($1.version) }
    }

    // MARK: - Loading

    private static func loadContent(from bundle: Bundle) -> WhatsNewContent {
        guard let url = bundle.url(forResource: "WhatsNew", withExtension: "json") else {
            logger.error("WhatsNew.json missing from bundle")
            return WhatsNewContent(releases: [])
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WhatsNewContent.self, from: data)
        } catch {
            logger.error("Failed to decode WhatsNew.json: \(error.localizedDescription)")
            return WhatsNewContent(releases: [])
        }
    }
}
