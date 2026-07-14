import Foundation
import Testing
@testable import Networking

struct QueryExpectation: Sendable, Equatable {
    let name: String
    let value: String?
}

struct EndpointExpectation: Sendable, CustomTestStringConvertible {
    let name: String
    let makeEndpoint: @Sendable () throws -> Endpoint
    let method: HTTPMethod
    let path: String
    let query: [QueryExpectation]
    let requiresAuth: Bool
    let canonicalBody: String?

    var testDescription: String { name }
}

let backendReconciledEndpointExpectations: [EndpointExpectation] = [
    EndpointExpectation(
        name: "public book detail",
        makeEndpoint: { Endpoints.getBook(id: "book-1") },
        method: .get,
        path: "/book/books/book-1",
        query: [],
        requiresAuth: false,
        canonicalBody: nil
    ),
    EndpointExpectation(
        name: "public download manifest",
        makeEndpoint: { Endpoints.getManifestForDownload(bookId: "book-1") },
        method: .get,
        path: "/book/books/book-1",
        query: [],
        requiresAuth: false,
        canonicalBody: nil
    ),
    EndpointExpectation(
        name: "tier read",
        makeEndpoint: { try Endpoints.postTier() },
        method: .get,
        path: "/book/me/tier",
        query: [],
        requiresAuth: true,
        canonicalBody: nil
    ),
    EndpointExpectation(
        name: "audio narration plan",
        makeEndpoint: { Endpoints.getAudioPlan(bookId: "book-1", chapterNumber: 2) },
        method: .get,
        path: "/book/books/book-1/chapters/2/audio",
        query: [QueryExpectation(name: "mode", value: "plan")],
        requiresAuth: true,
        canonicalBody: nil
    ),
    EndpointExpectation(
        name: "fresh audio download plan",
        makeEndpoint: { Endpoints.getAudioPlanFreshURLs(bookId: "book-1", chapterNumber: 2) },
        method: .get,
        path: "/book/books/book-1/chapters/2/audio",
        query: [QueryExpectation(name: "mode", value: "plan")],
        requiresAuth: true,
        canonicalBody: nil
    ),
    EndpointExpectation(
        name: "onboarding progress patch",
        makeEndpoint: {
            try Endpoints.postOnboardingProgress(
                OnboardingProgressBody(
                    step: "readingPrefs",
                    interests: ["business"],
                    chapterOrder: "summary_first",
                    tone: "direct",
                    dailyGoal: 20,
                    reminderHour: 8,
                    reminderMinute: 30
                )
            )
        },
        method: .patch,
        path: "/book/me/onboarding/progress",
        query: [],
        requiresAuth: true,
        canonicalBody: #"{"chapterOrder":"summary_first","dailyGoal":20,"interests":["business"],"reminderHour":8,"reminderMinute":30,"step":"readingPrefs","tone":"direct"}"#
    ),
]

@Suite("Backend-reconciled endpoint contracts")
struct BackendContractEndpointTests {
    @Test(
        "Factory matches the current backend request contract",
        arguments: backendReconciledEndpointExpectations
    )
    func factoryMatchesBackend(_ expectation: EndpointExpectation) throws {
        let endpoint = try expectation.makeEndpoint()

        #expect(endpoint.method == expectation.method)
        #expect(endpoint.path == expectation.path)
        #expect(endpoint.requiresAuth == expectation.requiresAuth)
        #expect(
            endpoint.query.map { QueryExpectation(name: $0.name, value: $0.value) }
                == expectation.query
        )
        #expect(try canonicalJSONString(endpoint.httpBody) == expectation.canonicalBody)
    }
}

private func canonicalJSONString(_ data: Data?) throws -> String? {
    guard let data else { return nil }
    let object = try JSONSerialization.jsonObject(with: data)
    let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard let string = String(data: canonical, encoding: .utf8) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return string
}
