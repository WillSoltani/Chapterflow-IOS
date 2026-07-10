import Testing
import Foundation
@testable import Networking

// MARK: - Semantic version

@Suite("SemanticVersion — numeric, testable comparison")
struct SemanticVersionTests {

    @Test("2.10 is greater than 2.9 (not a string compare)")
    func minorGreaterThanNine() throws {
        let ten = try #require(SemanticVersion("2.10"))
        let nine = try #require(SemanticVersion("2.9"))
        #expect(ten > nine)
        #expect(nine < ten)
    }

    @Test("trailing zeros are equivalent")
    func trailingZerosEqual() throws {
        #expect(SemanticVersion("2.10") == SemanticVersion("2.10.0"))
        #expect(SemanticVersion("2") == SemanticVersion("2.0.0"))
    }

    @Test("patch differences compare correctly")
    func patchCompare() throws {
        let base = try #require(SemanticVersion("1.0.0"))
        let patch = try #require(SemanticVersion("1.0.1"))
        #expect(base < patch)
    }

    @Test("pre-release / build metadata is ignored")
    func metadataIgnored() throws {
        #expect(SemanticVersion("1.2.3-beta.1") == SemanticVersion("1.2.3"))
        #expect(SemanticVersion("1.2.3+build99") == SemanticVersion("1.2.3"))
    }

    @Test("non-numeric input fails to parse")
    func unparseable() {
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("abc") == nil)
    }
}

// MARK: - Pure gate evaluation (four states + fail-open)

@Suite("AppConfigGate — four states + fail-open")
struct AppConfigGateEvaluationTests {

    @Test("nil config fails open to .none")
    func nilConfigFailsOpen() {
        #expect(AppConfigGate.evaluate(config: nil, currentVersion: "1.0.0") == .none)
    }

    @Test("maintenance mode → .maintenance")
    func maintenance() {
        let config = IOSAppConfig(maintenanceMode: true, messageOfTheDay: "brb")
        #expect(AppConfigGate.evaluate(config: config, currentVersion: "1.0.0") == .maintenance(message: "brb"))
    }

    @Test("build below minSupportedVersion → .hardGate")
    func hardGate() {
        let config = IOSAppConfig(minSupportedVersion: "2.0.0")
        #expect(AppConfigGate.evaluate(config: config, currentVersion: "1.9.9") == .hardGate(message: nil))
    }

    @Test("build at minSupportedVersion is not gated")
    func atMinimumNotGated() {
        let config = IOSAppConfig(minSupportedVersion: "2.0.0")
        #expect(AppConfigGate.evaluate(config: config, currentVersion: "2.0.0") == .none)
    }

    @Test("newer latestVersion → .softNudge")
    func softNudge() {
        let config = IOSAppConfig(latestVersion: "2.10.0")
        let state = AppConfigGate.evaluate(config: config, currentVersion: "2.9.0")
        #expect(state == .softNudge(latestVersion: "2.10.0", message: nil))
    }

    @Test("build at latestVersion → .none")
    func atLatestNoNudge() {
        let config = IOSAppConfig(latestVersion: "2.4.0")
        #expect(AppConfigGate.evaluate(config: config, currentVersion: "2.4.0") == .none)
    }

    @Test("maintenance takes precedence over a hard gate")
    func maintenanceBeatsHardGate() {
        let config = IOSAppConfig(minSupportedVersion: "9.0.0", maintenanceMode: true)
        let state = AppConfigGate.evaluate(config: config, currentVersion: "1.0.0")
        #expect(state == .maintenance(message: nil))
    }

    @Test("hard gate takes precedence over a soft nudge")
    func hardGateBeatsSoftNudge() {
        let config = IOSAppConfig(minSupportedVersion: "2.0.0", latestVersion: "3.0.0")
        let state = AppConfigGate.evaluate(config: config, currentVersion: "1.5.0")
        #expect(state == .hardGate(message: nil))
    }

    @Test("unparseable current version fails open (no false lock)")
    func unparseableCurrentVersionFailsOpen() {
        let config = IOSAppConfig(minSupportedVersion: "2.0.0")
        #expect(AppConfigGate.evaluate(config: config, currentVersion: "") == .none)
    }

    @Test("absent version fields never gate")
    func absentFieldsNeverGate() {
        let config = IOSAppConfig(messageOfTheDay: "hello")
        #expect(AppConfigGate.evaluate(config: config, currentVersion: "1.0.0") == .none)
    }

    @Test("isBlocking is true only for hard gate and maintenance")
    func isBlockingFlag() {
        #expect(AppConfigGateState.hardGate(message: nil).isBlocking)
        #expect(AppConfigGateState.maintenance(message: nil).isBlocking)
        #expect(!AppConfigGateState.softNudge(latestVersion: "9", message: nil).isBlocking)
        #expect(!AppConfigGateState.none.isBlocking)
    }
}
