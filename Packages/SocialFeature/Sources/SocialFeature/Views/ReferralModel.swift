import Foundation
import Observation

/// View-model for the referral programme screens.
///
/// Owns loading the referral profile and attributing a code manually.
/// Reward state comes from the server — this model never grants or
/// computes rewards client-side.
@Observable
@MainActor
public final class ReferralModel {

    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    public enum ApplyPhase: Equatable, Sendable {
        case idle
        case submitting
        case success(String)
        case failure(String)
    }

    // MARK: - Published state

    public var referralProfile: ReferralProfile?
    public var phase: Phase = .idle
    public var applyPhase: ApplyPhase = .idle

    // MARK: - Private

    private let repository: any SocialRepository

    public init(repository: any SocialRepository) {
        self.repository = repository
    }

    // MARK: - Load

    public func load() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            referralProfile = try await repository.getReferralProfile()
            phase = .loaded
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Apply code

    /// Submits a referral code typed / pasted by the user.
    ///
    /// On success, reloads the referral profile so the reward list reflects the
    /// server's updated state. Never grants rewards client-side.
    public func applyCode(_ code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            applyPhase = .failure("Please enter a referral code.")
            return
        }
        applyPhase = .submitting
        do {
            let result = try await repository.applyReferralCode(trimmed)
            if result.success {
                applyPhase = .success(result.message ?? "Referral applied!")
                // Refresh so rewards list reflects server state.
                await load()
            } else {
                applyPhase = .failure(result.message ?? "Could not apply the code.")
            }
        } catch {
            applyPhase = .failure(error.localizedDescription)
        }
    }

    public func resetApplyPhase() {
        applyPhase = .idle
    }
}
