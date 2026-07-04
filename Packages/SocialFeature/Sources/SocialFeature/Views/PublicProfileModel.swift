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

    // MARK: - Profile state

    public private(set) var phase: Phase = .idle
    public private(set) var profile: PublicProfile?

    // MARK: - Safety state

    public private(set) var isBlocked: Bool = false
    public private(set) var isSubmittingBlock: Bool = false
    public private(set) var isSubmittingReport: Bool = false
    public private(set) var reportSuccess: Bool = false

    /// Set when a safety action (block / report) fails.
    public private(set) var safetyError: String?

    /// Controls presentation of ``ReportView`` sheet.
    public var showReportSheet: Bool = false

    /// Controls presentation of ``BlockConfirmationView`` sheet.
    public var showBlockConfirmation: Bool = false

    private let userId: String
    private let repository: any SocialRepository

    // MARK: - Init

    public init(userId: String, repository: any SocialRepository) {
        self.userId = userId
        self.repository = repository
    }

    // MARK: - Profile actions

    public func load() async {
        phase = .loading
        do {
            async let profileResult = repository.getPublicProfile(userId: userId)
            async let blockedResult = repository.isBlocked(userId: userId)
            profile = try await profileResult
            isBlocked = await blockedResult
            phase = .loaded
        } catch let appError as AppError {
            phase = .error(appError.errorDescription ?? appError.code)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Safety actions

    /// Blocks the user being viewed. Call after the user confirms in ``BlockConfirmationView``.
    public func blockUser() async {
        isSubmittingBlock = true
        safetyError = nil
        do {
            try await repository.blockUser(userId: userId)
            isBlocked = true
        } catch let appError as AppError {
            safetyError = appError.errorDescription ?? appError.code
        } catch {
            safetyError = error.localizedDescription
        }
        isSubmittingBlock = false
        showBlockConfirmation = false
    }

    /// Unblocks the user being viewed.
    public func unblockUser() async {
        isSubmittingBlock = true
        safetyError = nil
        do {
            try await repository.unblockUser(userId: userId)
            isBlocked = false
        } catch let appError as AppError {
            safetyError = appError.errorDescription ?? appError.code
        } catch {
            safetyError = error.localizedDescription
        }
        isSubmittingBlock = false
    }

    /// Submits a moderation report for this user. Dismisses ``ReportView`` on success.
    public func submitReport(reason: ReportReason, details: String) async {
        isSubmittingReport = true
        safetyError = nil
        reportSuccess = false
        do {
            _ = try await repository.submitReport(
                targetUserId: userId,
                contentId: nil,
                contentType: nil,
                reason: reason,
                details: details.isEmpty ? nil : details
            )
            reportSuccess = true
            showReportSheet = false
        } catch let appError as AppError {
            safetyError = appError.errorDescription ?? appError.code
        } catch {
            safetyError = error.localizedDescription
        }
        isSubmittingReport = false
    }
}
