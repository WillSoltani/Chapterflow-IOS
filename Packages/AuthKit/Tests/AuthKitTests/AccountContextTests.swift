import CoreKit
import Foundation
import Testing
@testable import AuthKit

@Suite("Account context authority")
struct AccountContextTests {
    @Test("same account and environment keep namespaces but create a new scope instance")
    func stableNamespacesHaveUniqueInstances() throws {
        let identity = try makeIdentity(
            subject: "subject-account-a",
            username: "reader-a",
            email: "reader-a@example.test"
        )
        let config = try makeValidatedConfig()

        let first = AccountContext(identity: identity, config: config)
        let second = AccountContext(identity: identity, config: config)

        #expect(first.accountID == identity.subject)
        #expect(first.source == identity.source)
        #expect(first.environmentNamespace == second.environmentNamespace)
        #expect(first.storageNamespace == second.storageNamespace)
        #expect(first.instanceID != second.instanceID)
        #expect(first != second)
    }

    @Test("hermetic account context matches production namespace derivation")
    @MainActor
    func hermeticAccountContextMatchesProductionDerivation() throws {
        let config = try makeValidatedConfig(
            userPoolID: "us-east-1_ChapterFlowUITest",
            clientID: "chapterflowuitestclient12345",
            domain: "auth.chapterflow.test"
        )
        let expected = AccountContext(
            identity: SessionManager.hermeticUITestIdentity,
            config: config
        )
        let actual = SessionManager.hermeticUITestAccountContext(validatedConfig: config)

        #expect(actual.accountID == expected.accountID)
        #expect(actual.source == expected.source)
        #expect(actual.environmentNamespace == expected.environmentNamespace)
        #expect(actual.storageNamespace == expected.storageNamespace)
    }

    @Test("account and environment boundaries produce distinct opaque namespaces")
    func namespacesRespectAccountAndEnvironmentBoundaries() throws {
        let accountA = AccountContext(
            identity: try makeIdentity(subject: "subject-account-a"),
            config: try makeValidatedConfig()
        )
        let accountB = AccountContext(
            identity: try makeIdentity(subject: "subject-account-b"),
            config: try makeValidatedConfig()
        )
        let accountAInOtherEnvironment = AccountContext(
            identity: try makeIdentity(subject: "subject-account-a"),
            config: try makeValidatedConfig(apiBaseURL: "https://api.staging.chapterflow.test")
        )

        #expect(accountA.environmentNamespace == accountB.environmentNamespace)
        #expect(accountA.storageNamespace != accountB.storageNamespace)
        #expect(accountA.environmentNamespace != accountAInOtherEnvironment.environmentNamespace)
        #expect(accountA.storageNamespace != accountAInOtherEnvironment.storageNamespace)
    }

    @Test("description, debug output, and reflection redact identity and configuration")
    func diagnosticsAreRedacted() throws {
        let sensitiveValues = [
            "subject-private-123",
            "private-reader-name",
            "private-reader@example.test",
            "https://private-api.chapterflow.test",
            "us-east-1_PrivatePool123",
            "PrivateClient1234567890",
            "private.auth.us-east-1.amazoncognito.com",
        ]
        let context = AccountContext(
            identity: try makeIdentity(
                subject: sensitiveValues[0],
                username: sensitiveValues[1],
                email: sensitiveValues[2]
            ),
            config: try makeValidatedConfig(
                apiBaseURL: sensitiveValues[3],
                userPoolID: sensitiveValues[4],
                clientID: sensitiveValues[5],
                domain: sensitiveValues[6]
            )
        )
        let output = [
            String(describing: context),
            String(reflecting: context),
            context.customMirror.children
                .map { String(describing: $0.value) }
                .joined(separator: " "),
        ].joined(separator: " ")

        #expect(output.contains("redacted"))
        for sensitiveValue in sensitiveValues {
            #expect(!output.contains(sensitiveValue))
        }
        #expect(!context.environmentNamespace.contains("private"))
        #expect(!context.storageNamespace.contains("subject"))
    }

    @Test(
        "fallback subjects cannot become account context authority",
        arguments: ["", " ", " subject-with-whitespace ", "anon", "ANON", "local", "LOCAL"]
    )
    func invalidSubjectsFailBeforeContextConstruction(_ subject: String) {
        #expect(SessionIdentity(
            subject: subject,
            username: "reader",
            email: "reader@example.test",
            source: .cognitoUserPool
        ) == nil)
    }

    private func makeIdentity(
        subject: String,
        username: String? = nil,
        email: String? = nil
    ) throws -> SessionIdentity {
        try #require(SessionIdentity(
            subject: subject,
            username: username,
            email: email,
            source: .cognitoUserPool
        ))
    }

    private func makeValidatedConfig(
        apiBaseURL: String = "https://api.chapterflow.test",
        userPoolID: String = "us-east-1_ChapterFlow123",
        clientID: String = "ChapterFlowClient1234567890",
        domain: String = "chapterflow.auth.us-east-1.amazoncognito.com"
    ) throws -> ValidatedAppConfig {
        let config = AppConfig(
            apiBaseURL: apiBaseURL,
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: userPoolID,
            cognitoClientID: clientID,
            cognitoDomain: domain
        )
        guard case let .valid(validated) = config.validate() else {
            Issue.record("Expected test configuration to be valid")
            throw TestSetupError.invalidConfiguration
        }
        return validated
    }

    private enum TestSetupError: Error {
        case invalidConfiguration
    }
}
