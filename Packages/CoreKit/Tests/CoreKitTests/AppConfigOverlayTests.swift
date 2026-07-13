import Testing
@testable import CoreKit

@Suite("App configuration overlays")
struct AppConfigOverlayTests {
    @Test("hermetic service overlay preserves StoreKit IDs and disables Sentry")
    func hermeticOverlayPreservesUnrelatedConfiguration() throws {
        let source = AppConfig(
            apiBaseURL: "https://source.chapterflow.test",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: "ca-central-1_SourcePool",
            cognitoClientID: "sourceclient1234567890",
            cognitoDomain: "auth.source.chapterflow.test",
            sentryDSN: "https://private-key@errors.chapterflow.test/project",
            storeKitMonthlyProductID: "monthly-source",
            storeKitAnnualProductID: "annual-source",
            storeKitAnnualUpfrontProductID: "upfront-source"
        )
        let requiredServices = AppConfig(
            apiBaseURL: "https://api.chapterflow.test",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_ChapterFlowUITest",
            cognitoClientID: "chapterflowuitestclient12345",
            cognitoDomain: "auth.chapterflow.test",
            sentryDSN: "must-not-be-used",
            storeKitMonthlyProductID: "must-not-be-used",
            storeKitAnnualProductID: "must-not-be-used",
            storeKitAnnualUpfrontProductID: "must-not-be-used"
        )

        let resolved = source.applyingHermeticServiceOverlay(requiredServices)

        #expect(resolved.apiBaseURL == requiredServices.apiBaseURL)
        #expect(resolved.cognitoRegion == requiredServices.cognitoRegion)
        #expect(resolved.cognitoUserPoolID == requiredServices.cognitoUserPoolID)
        #expect(resolved.cognitoClientID == requiredServices.cognitoClientID)
        #expect(resolved.cognitoDomain == requiredServices.cognitoDomain)
        #expect(resolved.sentryDSN.isEmpty)
        #expect(resolved.storeKitMonthlyProductID == source.storeKitMonthlyProductID)
        #expect(resolved.storeKitAnnualProductID == source.storeKitAnnualProductID)
        #expect(resolved.storeKitAnnualUpfrontProductID == source.storeKitAnnualUpfrontProductID)

        guard case .valid(let validated) = resolved.validate() else {
            Issue.record("The active hermetic overlay should remain a valid configuration")
            return
        }
        #expect(validated.value.storeKitMonthlyProductID == "monthly-source")
        #expect(validated.value.storeKitAnnualProductID == "annual-source")
        #expect(validated.value.storeKitAnnualUpfrontProductID == "upfront-source")
        #expect(validated.value.sentryDSN.isEmpty)
    }
}
