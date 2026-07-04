import Foundation
import SwiftUI
import Models
import Networking
import CoreKit

// MARK: - ScenarioLoadState

public enum ScenarioLoadState {
    case idle
    case loading
    case loaded(ScenariosResponse)
    case error(String)
}

// MARK: - ScenariosModel

/// View model for the Scenarios hub and compose flow.
///
/// Owns the fetch, submit, and validation lifecycle. Status and points are
/// server-authoritative — this model never grants points locally.
@Observable
@MainActor
public final class ScenariosModel {

    // MARK: Dependencies

    private let repository: ScenarioRepository
    public let bookId: String
    public let chapterNumber: Int

    // MARK: State

    public private(set) var loadState: ScenarioLoadState = .idle
    public private(set) var isSubmitting: Bool = false
    public private(set) var submitError: String?
    public private(set) var pendingCount: Int = 0

    // MARK: Compose form fields

    public var title: String = ""
    public var scenario: String = ""
    public var whatToDo: String = ""
    public var whyItMatters: String = ""
    public var selectedScope: ScenarioScope = .work

    // MARK: Init

    public init(repository: ScenarioRepository, bookId: String, chapterNumber: Int) {
        self.repository = repository
        self.bookId = bookId
        self.chapterNumber = chapterNumber
    }

    // MARK: - Load

    public func load() {
        guard case .idle = loadState else { return }
        loadState = .loading
        Task {
            await fetchScenarios()
        }
    }

    public func refresh() async {
        await fetchScenarios(forceRefresh: true)
    }

    private func fetchScenarios(forceRefresh: Bool = false) async {
        do {
            let resp = try await repository.fetchScenarios(
                bookId: bookId,
                chapterNumber: chapterNumber,
                forceRefresh: forceRefresh
            )
            let pending = await repository.pendingUploadCount()
            loadState = .loaded(resp)
            pendingCount = pending
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Validation

    /// Whether the compose form is ready to submit.
    public var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !whatToDo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && {
            switch selectedScope {
            case .unknown: return false
            default: return true
            }
        }()
    }

    public var titleCharCount: Int { title.count }
    public var scenarioCharCount: Int { scenario.count }
    public var whatToDoCharCount: Int { whatToDo.count }
    public var whyItMattersCharCount: Int { whyItMatters.count }

    public static let titleLimit = 80
    public static let fieldLimit = 600

    public var isTitleOverLimit: Bool { titleCharCount > Self.titleLimit }
    public var isScenarioOverLimit: Bool { scenarioCharCount > Self.fieldLimit }
    public var isWhatToDoOverLimit: Bool { whatToDoCharCount > Self.fieldLimit }
    public var isWhyItMattersOverLimit: Bool { whyItMattersCharCount > Self.fieldLimit }

    public var hasAnyOverLimit: Bool {
        isTitleOverLimit || isScenarioOverLimit || isWhatToDoOverLimit || isWhyItMattersOverLimit
    }

    // MARK: - Submit

    /// Submits the composed scenario. Returns the created scenario on success.
    ///
    /// - Throws: `AppError` on network failure (non-offline).
    @discardableResult
    public func submitScenario() async throws -> UserScenario {
        guard isFormValid, !hasAnyOverLimit else {
            throw AppError.server(
                code: "validation_error",
                message: "Please complete all fields within character limits.",
                requestId: nil
            )
        }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            let body = ScenarioPostBody(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                scenario: scenario.trimmingCharacters(in: .whitespacesAndNewlines),
                whatToDo: whatToDo.trimmingCharacters(in: .whitespacesAndNewlines),
                whyItMatters: whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines),
                scope: selectedScope.rawValue
            )
            let created = try await repository.submitScenario(
                bookId: bookId,
                chapterNumber: chapterNumber,
                body: body,
                scope: selectedScope
            )
            resetForm()
            await fetchScenarios(forceRefresh: true)
            return created
        } catch {
            submitError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Form helpers

    public func resetForm() {
        title = ""
        scenario = ""
        whatToDo = ""
        whyItMatters = ""
        selectedScope = .work
        submitError = nil
    }

    // MARK: - Derived accessors

    public var myScenarios: [UserScenario] {
        guard case .loaded(let resp) = loadState else { return [] }
        return resp.scenarios
    }

    public var communityScenarios: [CommunityScenario] {
        guard case .loaded(let resp) = loadState else { return [] }
        return resp.community
    }
}
