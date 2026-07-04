import CoreKit
import Networking

// MARK: - Protocol

/// Persists onboarding progress and final choices to the server.
public protocol OnboardingRepository: Sendable {
    /// Fetches the user's saved onboarding state.
    /// Returns `nil` when no progress exists yet (new user).
    func fetchProgress() async throws -> OnboardingServerProgress?

    /// Saves the current step and accumulated choices mid-flow.
    func saveProgress(_ body: OnboardingProgressBody) async throws

    /// Finalises onboarding with the user's complete set of choices.
    func complete(_ body: OnboardingCompleteBody) async throws
}

// MARK: - Live implementation

/// The network-backed onboarding repository.
public actor LiveOnboardingRepository: OnboardingRepository {
    private let apiClient: any APIClientProtocol

    public init(apiClient: some APIClientProtocol) {
        self.apiClient = apiClient
    }

    public func fetchProgress() async throws -> OnboardingServerProgress? {
        do {
            let resp: OnboardingGetProgressResponse = try await apiClient.send(
                Endpoints.getOnboardingProgress()
            )
            return resp.progress
        } catch AppError.notFound {
            return nil
        }
    }

    public func saveProgress(_ body: OnboardingProgressBody) async throws {
        let endpoint = try Endpoints.postOnboardingProgress(body)
        let _: OnboardingAckResponse = try await apiClient.send(endpoint)
    }

    public func complete(_ body: OnboardingCompleteBody) async throws {
        let endpoint = try Endpoints.postOnboardingComplete(body)
        let _: OnboardingAckResponse = try await apiClient.send(endpoint)
    }
}

// MARK: - Mock (previews and tests)

/// An in-memory onboarding repository for previews and unit tests.
public actor MockOnboardingRepository: OnboardingRepository {
    public var stubbedProgress: OnboardingServerProgress?
    public var savedProgressBodies: [OnboardingProgressBody] = []
    public var completeBodies: [OnboardingCompleteBody] = []
    public var fetchShouldThrow: (any Error)?
    public var saveShouldThrow: (any Error)?

    public init(stubbedProgress: OnboardingServerProgress? = nil) {
        self.stubbedProgress = stubbedProgress
    }

    public func fetchProgress() async throws -> OnboardingServerProgress? {
        if let error = fetchShouldThrow { throw error }
        return stubbedProgress
    }

    public func saveProgress(_ body: OnboardingProgressBody) async throws {
        if let error = saveShouldThrow { throw error }
        savedProgressBodies.append(body)
    }

    public func complete(_ body: OnboardingCompleteBody) async throws {
        completeBodies.append(body)
    }
}
