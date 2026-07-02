import Foundation
import Observation
import CoreKit

/// Observable model driving ``PublicProfileView`` (read-only partner profile).
@Observable
@MainActor
public final class PublicProfileModel {

    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - State

    public private(set) var phase: Phase = .idle
    public private(set) var profile: PublicProfile?

    private let userId: String
    private let repository: any SocialRepository

    // MARK: - Init

    public init(userId: String, repository: any SocialRepository) {
        self.userId = userId
        self.repository = repository
    }

    // MARK: - Actions

    public func load() async {
        phase = .loading
        do {
            profile = try await repository.getPublicProfile(userId: userId)
            phase = .loaded
        } catch let appError as AppError {
            phase = .error(appError.errorDescription ?? appError.code)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}
