import Foundation
import Observation
import CoreKit

/// Observable model driving ``PrivacySettingsView``.
///
/// Holds the user's current ``PrivacySettings`` and persists any change
/// to the server immediately via `PATCH /book/me/settings`.
///
/// Each toggle in the view calls ``save()`` after mutating `settings`; the
/// model debounces to avoid hammering the network on rapid toggling.
@Observable
@MainActor
public final class PrivacySettingsModel {

    public enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    // MARK: - State

    public var settings: PrivacySettings
    public private(set) var saveState: SaveState = .idle

    // MARK: - Dependencies

    private let repository: any SocialRepository
    private var pendingSaveTask: Task<Void, Never>?

    // MARK: - Init

    public init(settings: PrivacySettings, repository: any SocialRepository) {
        self.settings = settings
        self.repository = repository
    }

    // MARK: - Actions

    /// Persists the current ``settings`` snapshot to the server.
    ///
    /// Safe to call after every toggle — debounces on the main actor so
    /// rapid changes coalesce into a single PATCH request.
    public func save() async {
        // Cancel any in-flight debounce task, then start a fresh one.
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            // Tiny debounce: let the UI settle before hitting the network.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSave()
        }
    }

    // MARK: - Private

    private func performSave() async {
        saveState = .saving
        do {
            let body = UpdateSettingsBody(privacySettings: settings)
            _ = try await repository.updateSettings(body)
            saveState = .saved
        } catch let appError as AppError {
            saveState = .error(appError.errorDescription ?? appError.code)
        } catch {
            saveState = .error(error.localizedDescription)
        }
    }
}
