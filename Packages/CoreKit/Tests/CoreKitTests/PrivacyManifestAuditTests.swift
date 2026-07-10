import Testing
import Foundation

/// P10.13 — regression guard for the security & privacy audit.
///
/// Validates that every shipping target's `PrivacyInfo.xcprivacy` exists, is a
/// well-formed plist, declares NO tracking, and declares its required-reason API
/// usage. These files are app/extension resources (not SPM resources), so the
/// suite locates the repo root from `#filePath` and reads them directly.
@Suite("Privacy manifest audit")
struct PrivacyManifestAuditTests {

    /// Walks up from this source file until it finds the directory containing
    /// `ChapterFlow.xcodeproj`. Returns nil if the package is checked out in
    /// isolation (outside the monorepo).
    static func repoRoot(from filePath: String = #filePath) -> URL? {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("ChapterFlow.xcodeproj").path
            ) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// (relative path, whether the target must declare the UserDefaults category).
    static let manifests: [(path: String, usesUserDefaults: Bool)] = [
        ("ChapterFlow/PrivacyInfo.xcprivacy", true),
        ("ChapterflowWidgets/PrivacyInfo.xcprivacy", true),
        ("ShareExtension/PrivacyInfo.xcprivacy", true),
        ("ActionExtension/PrivacyInfo.xcprivacy", true),
        ("NotificationService/PrivacyInfo.xcprivacy", false),
        ("NotificationContent/PrivacyInfo.xcprivacy", false)
    ]

    private func load(_ relative: String) throws -> [String: Any] {
        let root = try #require(Self.repoRoot(), "repo root not found from #filePath")
        let url = root.appendingPathComponent(relative)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any], "manifest is not a dictionary: \(relative)")
    }

    @Test("every shipping target has a valid privacy manifest", arguments: manifests)
    func manifestIsValid(entry: (path: String, usesUserDefaults: Bool)) throws {
        // Skip cleanly when checked out outside the monorepo (isolated package).
        try withKnownIssueIfNoRepo {
            let dict = try load(entry.path)

            // No tracking anywhere.
            let tracking = try #require(dict["NSPrivacyTracking"] as? Bool)
            #expect(tracking == false)
            let domains = dict["NSPrivacyTrackingDomains"] as? [String] ?? []
            #expect(domains.isEmpty, "tracking domains must be empty when tracking is off")

            // Required keys are present (arrays).
            #expect(dict["NSPrivacyCollectedDataTypes"] is [Any])
            let apis = try #require(dict["NSPrivacyAccessedAPITypes"] as? [[String: Any]])

            let userDefaults = apis.first {
                $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
            }
            if entry.usesUserDefaults {
                let ud = try #require(userDefaults, "\(entry.path) must declare UserDefaults")
                let reasons = try #require(ud["NSPrivacyAccessedAPITypeReasons"] as? [String])
                // Every reason must be a real UserDefaults reason code.
                let valid: Set<String> = ["CA92.1", "1C8F.1", "C56D.1", "AC6B.1"]
                #expect(!reasons.isEmpty)
                #expect(reasons.allSatisfy { valid.contains($0) })
            }
        }
    }

    @Test("main app declares the expected collected data types")
    func appCollectedDataTypes() throws {
        try withKnownIssueIfNoRepo {
            let dict = try load("ChapterFlow/PrivacyInfo.xcprivacy")
            let types = try #require(dict["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
            let ids = Set(types.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
            let expected: Set<String> = [
                "NSPrivacyCollectedDataTypeEmailAddress",
                "NSPrivacyCollectedDataTypeName",
                "NSPrivacyCollectedDataTypeUserID",
                "NSPrivacyCollectedDataTypePurchaseHistory",
                "NSPrivacyCollectedDataTypeOtherUserContent",
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeCrashData",
                "NSPrivacyCollectedDataTypePerformanceData",
                "NSPrivacyCollectedDataTypeOtherDiagnosticData"
            ]
            #expect(ids == expected)
            // Nothing is flagged as used for tracking.
            for type in types {
                #expect((type["NSPrivacyCollectedDataTypeTracking"] as? Bool) == false)
            }
        }
    }

    /// Runs `body`; if the repo root can't be found (isolated checkout), records a
    /// known issue instead of failing so the package still builds standalone.
    private func withKnownIssueIfNoRepo(_ body: () throws -> Void) throws {
        if Self.repoRoot() == nil {
            withKnownIssue("privacy manifests unavailable outside the monorepo") {
                try body()
            }
        } else {
            try body()
        }
    }
}
