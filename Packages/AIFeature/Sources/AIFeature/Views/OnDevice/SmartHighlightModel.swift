import Foundation
import Observation

// MARK: - Model

/// View model for surfacing key-sentence highlight suggestions on-device.
///
/// Feed it chapter text and call ``loadSuggestions()`` once the chapter is
/// visible. Suggestions are shown non-intrusively via ``SmartHighlightBanner``.
///
/// The model is entirely silent on failure — the banner simply hides.
/// Never block the reader UI waiting for this model.
@Observable
@MainActor
public final class SmartHighlightModel {

    // MARK: - State

    /// Key sentences surfaced as highlight candidates. Empty until loaded.
    public private(set) var suggestions: [String] = []

    /// True while generation is in progress.
    public private(set) var isLoading: Bool = false

    // MARK: - Config

    private let chapterText: String
    private let service: any OnDeviceAIProviding
    private let count: Int

    // MARK: - Init

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - chapterText: Plain text of the chapter; empty text silences the model.
    ///   - service: The on-device AI provider; must already be available.
    ///   - count: Number of highlight candidates to request (default 3).
    public init(
        chapterText: String,
        service: any OnDeviceAIProviding,
        count: Int = 3
    ) {
        self.chapterText = chapterText
        self.service = service
        self.count = count
    }

    // MARK: - Actions

    /// Fetches highlight suggestions. No-op if already loaded or loading.
    /// Failures are silently swallowed — the banner simply stays hidden.
    public func loadSuggestions() async {
        guard suggestions.isEmpty, !isLoading, !chapterText.isEmpty else { return }
        let state = await service.availability
        guard state.isAvailable else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            suggestions = try await service.suggestHighlights(from: chapterText, count: count)
        } catch {
            suggestions = []
        }
    }

    /// Dismisses a specific suggestion (e.g. after the user has highlighted it).
    public func dismiss(_ suggestion: String) {
        suggestions.removeAll { $0 == suggestion }
    }

    /// Clears all suggestions (e.g. chapter changed).
    public func clearAll() {
        suggestions = []
    }
}
