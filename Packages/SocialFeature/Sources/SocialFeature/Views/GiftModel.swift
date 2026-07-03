import SwiftUI
import CoreKit

// MARK: - Phase types

/// The state machine for the gift-send flow.
public enum GiftSendPhase: Equatable {
    case idle
    case creating
    case created(Gift)
    case error(String)
}

/// The state machine for the gift-claim flow.
public enum GiftClaimPhase: Equatable {
    case idle
    case loadingPreview
    case preview(Gift)
    case claiming
    case claimed(GiftClaimResult)
    case error(String)
}

// MARK: - GiftModel

/// Observable model that drives both the gift-send and gift-claim flows.
///
/// Send flow:  `createGift()` → `.created(gift)` → user shares link.
/// Claim flow: `previewGift(code:)` → `.preview(gift)` → `claimGift(code:)` → `.claimed(result)`.
@Observable
@MainActor
public final class GiftModel {

    // MARK: State

    public private(set) var sendPhase: GiftSendPhase = .idle
    public private(set) var claimPhase: GiftClaimPhase = .idle

    /// Bound to the manual code-entry text field.
    public var codeInput: String = ""

    // MARK: Dependencies

    private let repository: any SocialRepository

    // MARK: Init

    public init(repository: any SocialRepository, initialCode: String? = nil) {
        self.repository = repository
        if let code = initialCode {
            codeInput = code
        }
    }

    // MARK: - Send flow

    /// Calls `POST /book/me/gifts` to generate a new shareable gift code.
    public func createGift(giftType: String = "pro_week") async {
        sendPhase = .creating
        do {
            let gift = try await repository.createGift(giftType: giftType)
            sendPhase = .created(gift)
        } catch let appError as AppError {
            sendPhase = .error(appError.errorDescription ?? "Something went wrong.")
        } catch {
            sendPhase = .error("Something went wrong. Please try again.")
        }
    }

    public func resetSend() {
        sendPhase = .idle
    }

    // MARK: - Claim flow

    /// Fetches gift details for preview without claiming.
    public func previewGift(code: String) async {
        let trimmed = normalized(code)
        guard !trimmed.isEmpty else { return }
        claimPhase = .loadingPreview
        do {
            let gift = try await repository.getGift(code: trimmed)
            claimPhase = .preview(gift)
        } catch let appError as AppError {
            claimPhase = .error(claimError(from: appError))
        } catch {
            claimPhase = .error("Something went wrong. Please try again.")
        }
    }

    /// Claims the gift, activating the entitlement server-side.
    ///
    /// On success the caller should re-fetch entitlements — never grant Pro client-side.
    public func claimGift(code: String) async {
        let trimmed = normalized(code)
        claimPhase = .claiming
        do {
            let result = try await repository.claimGift(code: trimmed)
            claimPhase = .claimed(result)
        } catch let appError as AppError {
            claimPhase = .error(claimError(from: appError))
        } catch {
            claimPhase = .error("Something went wrong. Please try again.")
        }
    }

    public func resetClaim() {
        claimPhase = .idle
        codeInput = ""
    }

    // MARK: - Helpers

    /// Strips whitespace and uppercases the code for consistent server calls.
    private func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func claimError(from error: AppError) -> String {
        if case .server(let serverCode, let message, _) = error {
            switch serverCode {
            case "gift_already_claimed":
                return "This gift has already been redeemed by someone else."
            case "gift_expired":
                return "This gift code has expired."
            case "gift_not_found":
                return "Gift code not found. Check the code and try again."
            default:
                return message.isEmpty ? "Something went wrong. Please try again." : message
            }
        }
        if case .notFound = error {
            return "Gift code not found. Check the code and try again."
        }
        return error.errorDescription ?? "Something went wrong. Please try again."
    }
}
