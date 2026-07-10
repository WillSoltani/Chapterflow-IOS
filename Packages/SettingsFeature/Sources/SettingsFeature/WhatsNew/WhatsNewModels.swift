import Foundation
import Models

// MARK: - WhatsNewHighlight

/// A single feature highlight shown on the What's New screen.
///
/// Decoded from the bundled `WhatsNew.json`. All fields are required; a
/// malformed highlight is dropped by ``WhatsNewRelease`` rather than crashing
/// the whole release (RF2 — tolerant collections).
public struct WhatsNewHighlight: Identifiable, Sendable, Hashable, Codable {
    /// Stable identifier used for `ForEach` and analytics.
    public let id: String
    /// SF Symbol name rendered in the leading badge.
    public let symbolName: String
    /// Short, benefit-led headline.
    public let title: String
    /// One or two sentences of supporting detail.
    public let detail: String

    public init(id: String, symbolName: String, title: String, detail: String) {
        self.id = id
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
    }
}

// MARK: - WhatsNewRelease

/// The release notes for a single app version.
public struct WhatsNewRelease: Identifiable, Sendable, Hashable, Codable {
    /// The marketing version these notes describe (e.g. `"1.2"`).
    public let version: String
    /// Screen title (e.g. `"What's New"` or `"Welcome to ChapterFlow"`).
    public let title: String
    /// The ordered feature highlights.
    public let highlights: [WhatsNewHighlight]

    public var id: String { version }

    public init(version: String, title: String, highlights: [WhatsNewHighlight]) {
        self.version = version
        self.title = title
        self.highlights = highlights
    }

    private enum CodingKeys: String, CodingKey {
        case version, title, highlights
    }

    /// Tolerant decoding (RF2): a single malformed highlight is dropped and the
    /// rest of the release survives.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.title = try container.decode(String.self, forKey: .title)
        self.highlights = (try? container.decodeLossy(WhatsNewHighlight.self, forKey: .highlights)) ?? []
    }
}

// MARK: - WhatsNewContent

/// The top-level bundled content: all shipped releases, newest last.
public struct WhatsNewContent: Sendable, Codable {
    public let releases: [WhatsNewRelease]

    public init(releases: [WhatsNewRelease]) {
        self.releases = releases
    }

    private enum CodingKeys: String, CodingKey {
        case releases
    }

    /// Tolerant decoding (RF2): a malformed release is dropped; the rest survive.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.releases = (try? container.decodeLossy(WhatsNewRelease.self, forKey: .releases)) ?? []
    }
}
