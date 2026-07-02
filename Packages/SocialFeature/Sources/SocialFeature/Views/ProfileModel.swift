import Foundation
import Observation
import Models
import CoreKit

/// Observable model driving ``ProfileView`` (own-profile tab).
///
/// Fetches profile, badges, and additional dashboard stats concurrently.
/// All mutations happen on the main actor; the repository is actor-isolated.
@Observable
@MainActor
public final class ProfileModel {

    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - State

    public private(set) var phase: Phase = .idle
    public private(set) var profile: OwnProfile?
    public private(set) var badges: [BadgeItem] = []

    // MARK: - Edit profile state

    public var editDisplayName: String = ""
    public private(set) var isSaving: Bool = false
    public private(set) var saveError: String?

    // MARK: - Dependencies

    private let repository: any SocialRepository

    // MARK: - Init

    public init(repository: any SocialRepository) {
        self.repository = repository
    }

    // MARK: - Actions

    /// Loads profile and badges concurrently. Safe to call multiple times (refreshable).
    public func load() async {
        phase = .loading
        do {
            async let profileTask = repository.getMyProfile()
            async let badgesTask = repository.getMyBadges()
            let (fetchedProfile, fetchedBadges) = try await (profileTask, badgesTask)
            profile = fetchedProfile
            badges = fetchedBadges.filter { $0.isEarned }
            editDisplayName = fetchedProfile.displayName ?? ""
            phase = .loaded
        } catch let appError as AppError {
            phase = .error(appError.errorDescription ?? appError.code)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Persists `editDisplayName` via `PATCH /book/me/settings` and refreshes
    /// the profile view.
    public func saveDisplayName() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let body = UpdateSettingsBody(displayName: editDisplayName.trimmingCharacters(in: .whitespaces))
            let updated = try await repository.updateSettings(body)
            profile = updated
        } catch let appError as AppError {
            saveError = appError.errorDescription ?? appError.code
        } catch {
            saveError = error.localizedDescription
        }
    }
}
