import Foundation
import Testing

private let expectedNativeOperationIDs: Set<String> = [
    "account-deactivate.post", "account-delete.post", "analytics-beacon.post",
    "analytics-track.post", "apple-verify.post", "ask-book.post", "audio-plan.get",
    "badges.get", "block-user.post", "blocked-user.delete", "blocked-users.get",
    "book-detail.get", "book-state.get", "book-state.patch", "catalog.get", "chapter.get",
    "commitment.get", "commitment.patch", "commitment.post", "commitments.get",
    "concept-graph.get", "dashboard.get", "depth-recommendation.get", "device-register.post",
    "device-unregister.post", "entitlements.get", "event-join.post", "event-progress.get",
    "event-progress.post", "export.get", "flow-points-redeem.post", "flow-points.get",
    "gift-claim.post", "gift-create.post", "gift-preview.get", "journey-start.post",
    "journeys.get", "mobile-config.get", "moderation-report.post", "notebook.delete",
    "notebook.get", "notebook.patch", "notebook.post", "notifications-read-all.post",
    "notifications.get", "onboarding-complete.post", "onboarding-progress.get",
    "onboarding-progress.post", "own-profile.get", "pair-accept.post", "pair-invite.post",
    "pair-nudge.post", "pair.delete", "pair.get", "pairs.get", "progress.get",
    "public-profile.get", "quiz-check.post", "quiz-event.post", "quiz-submit.post", "quiz.get",
    "reading-session.post", "referral-apply.post", "referral-profile.get",
    "reflection-feedback.post", "reflection.post", "reflections.get", "review-grade.post",
    "reviews.get", "saved-toggle.post", "saved.get", "scenario.post", "scenarios.get",
    "search-index.get", "seasonal-event.get", "settings.get", "settings.patch",
    "share-event.post", "shop.get", "start-book.post", "streak.get", "tier.post",
    "user-journey.get",
]

private let expectedMatrixRowIDs: Set<String> = [
    "catalog", "search-index", "book-detail-manifest", "entitlements-paywall",
    "progress-overview", "saved-books", "start-book", "book-state-cursor-preferences",
    "chapter-content", "quiz-load-check-events", "quiz-submit", "ask-the-book",
    "audio-narration-plan", "reading-sessions", "notebook", "fsrs-reviews", "commitments",
    "profile-social", "reading-pairs", "gifts-referrals", "notification-inbox",
    "notification-preferences", "apns-device-registration", "onboarding",
    "apple-purchase-verification", "data-export", "account-deactivation", "account-deletion",
    "mobile-config",
]

@Suite("Backend-owned native contract bundle")
struct NativeContractBundleTests {
    @Test("bundle validates against the complete native inventory")
    func completeInventory() throws {
        let bundle = try NativeContractBundleFixture.load()
        try validate(bundle)

        #expect(Set(bundle.operations.map(\.id)) == expectedNativeOperationIDs)
        #expect(Set(bundle.inventory.matrixRows.map(\.id)) == expectedMatrixRowIDs)
    }

    @Test("coverage remains partial or blocked until every proof gap is closed")
    func truthfulCoverage() throws {
        let bundle = try NativeContractBundleFixture.load()
        let partial = bundle.operations.filter { $0.coverage == "partial" }
        let blocked = bundle.operations.filter { $0.coverage == "blocked" }

        #expect(partial.count == 60)
        #expect(blocked.count == 23)
        #expect(!bundle.operations.contains { $0.coverage == "full" })
        for operation in partial {
            let kinds = Set(operation.gaps.map(\.kind))
            #expect(kinds.contains("route_specific_error_coverage"))
            #expect(kinds.contains("native_request_fixture_proof"))
            #expect(kinds.contains("native_response_consumer_proof"))
            #expect(kinds.contains("source_dependency_closure"))
        }

        let mobileConfig = try #require(bundle.operations.first { $0.id == "mobile-config.get" })
        #expect(mobileConfig.gaps.contains { $0.kind == "client_authority_enforcement" })
        let searchIndex = try #require(bundle.operations.first { $0.id == "search-index.get" })
        #expect(searchIndex.fixtures?.errors.isEmpty == true)
        #expect(searchIndex.gaps.contains { $0.kind == "external_response_asset" })
        #expect(searchIndex.gaps.contains { $0.kind == "client_response_projection" })
    }

    @Test("bundle pins the separately collected iOS inventory manifest")
    func inventoryManifest() throws {
        let bundle = try NativeContractBundleFixture.load()
        let manifest = try IOSSourceInventoryManifest.load()
        let evidence = bundle.inventory.iosSourceEvidence
        let inventoryRevision = "bb7ca30041dd095dc36144611bea127f0b53099d"
        #expect(evidence.manifestPath == "contracts/native-ios/v1/ios-source-inventory-manifest.json")
        #expect(evidence.iosBaseRevision == manifest.iosBaseRevision)
        #expect(evidence.iosSourceRevision == inventoryRevision)
        #expect(evidence.iosSourceRevisionPhase == "committed_contract_branch")
        #expect(manifest.iosSourceRevision == inventoryRevision)
        #expect(manifest.iosSourceRevisionPhase == "committed_contract_branch")
        #expect(evidence.operationKeySha256 == manifest.operationKeySha256)
        #expect(evidence.producerVariantIdSha256 == manifest.producerVariantIdSha256)
        #expect(evidence.exactFactoryTestedProducerCount == 6)
        #expect(evidence.bundleSuccessDecoderTestedOperationCount == 24)
        #expect(!evidence.backendRuntimeFactoryValidationPerformed)
        #expect(manifest.operationKeyCount == 83)
        #expect(manifest.producerVariantCount == 93)
        #expect(manifest.bundleSuccessDecoderTestedOperationCount == 24)
    }

    @Test("blocked operations retain native requests and backend mismatch evidence")
    func blockedOperationsRetainEvidence() throws {
        let bundle = try NativeContractBundleFixture.load()
        let blocked = bundle.operations.filter { $0.coverage == "blocked" }
        #expect(!blocked.isEmpty)
        for operation in blocked {
            #expect(!operation.nativeRequestFixtures.isEmpty)
            #expect(operation.blocker != nil)
            #expect(operation.fixtures == nil)
            #expect(operation.backend == nil)
        }
        let missingRoutes = blocked.filter { $0.blocker?.kind == "missing_route" }
        #expect(missingRoutes.count == 8)
        #expect(missingRoutes.allSatisfy { $0.blocker?.expectedRouteSource?.isEmpty == false })
    }

    @Test("request fixtures preserve ordered query items and body kind")
    func requestRepresentationIsLossless() throws {
        let bundle = try NativeContractBundleFixture.load()
        let requests = bundle.operations.flatMap(\.nativeRequestFixtures)

        #expect(requests.contains { $0.body.kind == "none" && $0.body.value == nil })
        #expect(requests.contains { $0.body.kind == "json" })

        let audio = try #require(
            bundle.operations.first { $0.id == "audio-plan.get" }?.nativeRequestFixtures.first
        )
        #expect(audio.queryItems == [ContractItem(name: "mode", value: .string("plan"))])
    }

    @Test("rate-limit errors carry Retry-After metadata")
    func retryAfterMetadata() throws {
        let bundle = try NativeContractBundleFixture.load()
        let rateLimits = bundle.operations.compactMap(\.fixtures).flatMap(\.errors)
            .filter { $0.status == 429 || $0.code == "rate_limited" }

        if bundle.retryAfterPolicy.implemented {
            #expect(rateLimits.count == bundle.retryAfterPolicy.fixtureCount)
            #expect(!rateLimits.isEmpty)
            for fixture in rateLimits {
                #expect(fixture.headers.contains { $0.name.lowercased() == "retry-after" })
            }
        } else {
            #expect(rateLimits.isEmpty)
            #expect(bundle.retryAfterPolicy.fixtureCount == 0)
            #expect(!bundle.retryAfterPolicy.evidence.isEmpty)
            #expect(!bundle.retryAfterPolicy.gap.isEmpty)
        }
    }

    @Test("a representative operation-key mutation trips the drift canary")
    func driftCanary() throws {
        var bundle = try NativeContractBundleFixture.load()
        bundle.operations[1].id = bundle.operations[0].id

        #expect(throws: NativeContractValidationError.self) {
            try validate(bundle)
        }
    }
}

private enum NativeContractValidationError: Error {
    case invalid(String)
}

private func validate(_ bundle: NativeContractBundleFixture) throws {
    try validateMetadata(bundle)
    try validateInventory(bundle)
    for operation in bundle.operations {
        try validate(operation)
    }
}

private func validateMetadata(_ bundle: NativeContractBundleFixture) throws {
    try requireContract(bundle.schemaVersion == "chapterflow-native-contract-bundle-v1", "schema version")
    try requireContract(bundle.contractVersion == "1", "contract version")
    try requireContract(
        bundle.provenance.backendRepository == "WillSoltani/ChapterFlow",
        "backend repository"
    )
    try requireContract(
        bundle.provenance.generatorVersion == "chapterflow-native-contract-generator-v1",
        "generator version"
    )
    try requireContract(bundle.provenance.syntheticDataOnly, "synthetic provenance")
    try requireContract(bundle.provenance.deployedRevision == nil, "deployed revision claim")
    try requireContract(
        !bundle.provenance.deployedRevisionVerified,
        "deployed revision verification claim"
    )
    try requireContract(bundle.provenance.behaviorSourceRevision.count == 40, "behavior revision")
    try requireContract(
        ISO8601DateFormatter().date(from: bundle.provenance.behaviorSourceTimestamp) != nil,
        "behavior source timestamp"
    )
    try requireContract(bundle.provenance.generatorTreeDigest.count == 64, "generator digest")
    try requireContract(
        ISO8601DateFormatter().date(from: bundle.provenance.generatedAt) != nil,
        "generated timestamp"
    )
    switch bundle.provenance.sourceRevisionPhase {
    case "uncommitted_backend":
        throw NativeContractValidationError.invalid("iOS bundle must pin a committed backend revision")
    case "committed_backend_branch", "merged_backend":
        guard let sourceRevision = bundle.provenance.sourceRevision else {
            throw NativeContractValidationError.invalid("committed source revision")
        }
        try requireContract(isLowercaseGitSHA(sourceRevision), "committed source revision format")
    default:
        throw NativeContractValidationError.invalid("source revision phase")
    }
}

private func validateInventory(_ bundle: NativeContractBundleFixture) throws {
    try requireContract(bundle.inventory.uniqueOperationCount == 83, "operation count")
    try requireContract(bundle.inventory.nativeProducerCount == 93, "producer count")
    try requireContract(bundle.inventory.matrixRowCount == 29, "matrix count")
    try requireContract(
        bundle.operations.count == bundle.inventory.uniqueOperationCount,
        "operation summary"
    )

    let operationIDs = bundle.operations.map(\.id)
    try requireContract(Set(operationIDs).count == operationIDs.count, "duplicate operation id")
    let methodRoutes = bundle.operations.map { "\($0.method) \($0.routeTemplate)" }
    try requireContract(Set(methodRoutes).count == methodRoutes.count, "duplicate method and route")
    try requireContract(Set(operationIDs) == expectedNativeOperationIDs, "operation set")
    try requireContract(
        Set(bundle.inventory.matrixRows.map(\.id)) == expectedMatrixRowIDs,
        "matrix set"
    )

    let requests = bundle.operations.flatMap(\.nativeRequestFixtures)
    try requireContract(requests.count == bundle.inventory.nativeProducerCount, "producer summary")
    let variantIDs = requests.map(\.operationVariantId)
    try requireContract(Set(variantIDs).count == variantIDs.count, "duplicate request variant")
    try requireContract(
        bundle.inventory.iosSourceEvidence.iosBaseRevision
            == "92a5c351a42771f546b3d0e575b3b37a8cbfb588",
        "iOS inventory base revision"
    )
    try requireContract(
        bundle.inventory.iosSourceEvidence.iosSourceRevision
            == "bb7ca30041dd095dc36144611bea127f0b53099d"
            && bundle.inventory.iosSourceEvidence.iosSourceRevisionPhase
                == "committed_contract_branch",
        "iOS inventory branch provenance"
    )
    try requireContract(
        bundle.inventory.iosSourceEvidence.exactFactoryTestedProducerCount == 6,
        "exact factory proof count"
    )
    try requireContract(
        bundle.inventory.iosSourceEvidence.bundleSuccessDecoderTestedOperationCount == 24,
        "bundle success consumer proof count"
    )
    try requireContract(
        !bundle.inventory.iosSourceEvidence.backendRuntimeFactoryValidationPerformed,
        "backend Swift execution claim"
    )
}

private func validate(_ operation: NativeContractBundleFixture.Operation) throws {
    try requireContract(operation.routeTemplate.hasPrefix("/book/"), "native route")
    try requireContract(!operation.nativeRequestFixtures.isEmpty, "native requests")
    try requireContract(!operation.responseContract.iosModels.isEmpty, "response models")
    try requireContract(!operation.responseContract.decoders.isEmpty, "decoders")
    try requireContract(!operation.ios.factories.isEmpty, "factories")
    try requireContract(!operation.ios.callSites.isEmpty, "call sites")
    try requireContract(!operation.evidence.isEmpty, "operation evidence")

    if operation.coverage == "blocked" {
        try requireContract(operation.blocker != nil, "blocked evidence")
        try requireContract(operation.backend == nil && operation.fixtures == nil, "blocked fixtures")
        return
    }

    let backend = try requireValue(operation.backend, "backend evidence")
    let fixtures = try requireValue(operation.fixtures, "fixtures")
    try requireContract(operation.blocker == nil, "covered blocker")
    if operation.coverage == "full" {
        try requireContract(!fixtures.errors.isEmpty, "documented errors")
    } else {
        try requireContract(!operation.gaps.isEmpty, "partial proof gaps")
    }
    try requireContract(
        fixtures.request.operationVariantId == fixtures.requestVariants.first?.operationVariantId,
        "primary request variant"
    )
    let canonicalNative = Set(
        operation.nativeRequestFixtures
            .filter { $0.compatibility == "canonical" }
            .map(\.operationVariantId)
    )
    try requireContract(
        Set(fixtures.requestVariants.map(\.operationVariantId)) == canonicalNative,
        "canonical request variant set"
    )
    if operation.coverage == "full" {
        try requireContract(backend.serializerProof.kind == "executed_pure_builder", "full serializer proof")
    }
    try requireContract(
        Set(fixtures.success.requiredAuthorityFields)
            == Set(operation.authority.expectedRequiredPointers),
        "authority pointers"
    )
    if operation.authority.failureMode == "fail_closed" {
        try requireContract(!operation.authority.expectedRequiredPointers.isEmpty, "fail-closed pointers")
    }
    if case .json(let value) = fixtures.success.payload {
        for pointer in fixtures.success.requiredAuthorityFields {
            try requireContract(value.has(pointer: pointer), "authority payload pointer")
        }
    }
    for alias in fixtures.deployedCompatibleSuccessAliases {
        try requireContract(!alias.aliasId.isEmpty, "alias id")
        try requireContract(!alias.provenance.evidence.isEmpty, "alias provenance")
        try requireContract(!alias.evidence.isEmpty, "alias evidence")
    }
    for error in fixtures.errors {
        try requireContract(error.code == error.body.error.code, "error envelope code")
        try requireContract(
            error.body.error.requestId.hasPrefix("req_synthetic_"),
            "synthetic request id"
        )
    }
}

private func requireContract(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NativeContractValidationError.invalid(message) }
}
private func isLowercaseGitSHA(_ value: String) -> Bool {
    value.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil
}

private func requireValue<Value>(_ value: Value?, _ message: String) throws -> Value {
    guard let value else { throw NativeContractValidationError.invalid(message) }
    return value
}

private struct NativeContractBundleFixture: Decodable, Sendable {
    let schemaVersion: String
    let contractVersion: String
    let provenance: Provenance
    let inventory: Inventory
    let retryAfterPolicy: RetryAfterPolicy
    var operations: [Operation]

    static func load() throws -> Self {
        let data = try Data(contentsOf: bundleURL())
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private static func bundleURL() -> URL {
        contractRepositoryRoot()
            .appending(path: "contracts/native-ios/v1/contract-bundle.json")
    }

    struct Provenance: Decodable, Sendable {
        let backendRepository: String
        let sourceRevision: String?
        let behaviorSourceRevision: String
        let behaviorSourceTimestamp: String
        let sourceRevisionPhase: String
        let generatedAt: String
        let generatorVersion: String
        let generatorTreeDigest: String
        let syntheticDataOnly: Bool
        let deployedRevision: String?
        let deployedRevisionVerified: Bool
    }

    struct Inventory: Decodable, Sendable {
        let uniqueOperationCount: Int
        let nativeProducerCount: Int
        let matrixRowCount: Int
        let iosSourceEvidence: IOSSourceEvidence
        let matrixRows: [MatrixRow]

        struct IOSSourceEvidence: Decodable, Sendable {
            let manifestPath: String
            let iosBaseRevision: String
            let iosSourceRevision: String?
            let iosSourceRevisionPhase: String
            let operationKeySha256: String
            let producerVariantIdSha256: String
            let exactFactoryTestedProducerCount: Int
            let bundleSuccessDecoderTestedOperationCount: Int
            let backendRuntimeFactoryValidationPerformed: Bool
        }

        struct MatrixRow: Decodable, Sendable {
            let id: String
            let operationIds: [String]
        }
    }

    struct RetryAfterPolicy: Decodable, Sendable {
        let implemented: Bool
        let fixtureCount: Int
        let evidence: [String]
        let gap: String
    }

    struct Operation: Decodable, Sendable {
        var id: String
        let method: String
        let routeTemplate: String
        let matrixRowId: String?
        let nativeRequestFixtures: [Request]
        let responseContract: ResponseContract
        let authority: Authority
        let ios: IOS
        let coverage: String
        let gaps: [Gap]
        let backend: Backend?
        let blocker: Blocker?
        let fixtures: Fixtures?
        let evidence: [String]

        struct Gap: Decodable, Sendable {
            let kind: String
            let reason: String
        }

        struct ResponseContract: Decodable, Sendable {
            let iosModels: [String]
            let decoders: [String]
        }

        struct Authority: Decodable, Sendable {
            let expectedRequiredPointers: [String]
            let failureMode: String
        }

        struct IOS: Decodable, Sendable {
            let factories: [String]
            let callSites: [String]
        }

        struct Backend: Decodable, Sendable {
            let serializerProof: SerializerProof

            struct SerializerProof: Decodable, Sendable { let kind: String }
        }

        struct Blocker: Decodable, Sendable {
            let kind: String
            let evidence: [String]
            let expectedRouteSource: String?
        }

        struct Fixtures: Decodable, Sendable {
            let request: Request
            let requestVariants: [Request]
            let success: Success
            let deployedCompatibleSuccessAliases: [Alias]
            let errors: [ErrorFixture]

            struct Success: Decodable, Sendable {
                let payload: ContractPayload
                let requiredAuthorityFields: [String]
            }

            struct Alias: Decodable, Sendable {
                let aliasId: String
                let provenance: AliasProvenance
                let evidence: [String]

                struct AliasProvenance: Decodable, Sendable { let evidence: [String] }
            }
        }
    }
}

private struct IOSSourceInventoryManifest: Decodable, Sendable {
    let iosBaseRevision: String
    let iosSourceRevision: String?
    let iosSourceRevisionPhase: String
    let operationKeyCount: Int
    let operationKeySha256: String
    let producerVariantCount: Int
    let producerVariantIdSha256: String
    let bundleSuccessDecoderTestedOperationCount: Int

    static func load() throws -> Self {
        let url = contractRepositoryRoot()
            .appending(path: "contracts/native-ios/v1/ios-source-inventory-manifest.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

private func contractRepositoryRoot() -> URL {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return root
}

private struct Request: Decodable, Sendable {
    let operationVariantId: String
    let queryItems: [ContractItem]
    let body: ContractBody
    let compatibility: String
}

private struct ContractBody: Decodable, Sendable {
    let kind: String
    let value: ContractJSONValue?
}

private struct ContractItem: Decodable, Sendable, Equatable {
    let name: String
    let value: ContractJSONValue
}

private enum ContractPayload: Decodable, Sendable {
    case json(ContractJSONValue)
    case other

    private enum CodingKeys: String, CodingKey { case kind, value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(String.self, forKey: .kind) == "json" {
            self = .json(try container.decode(ContractJSONValue.self, forKey: .value))
        } else {
            self = .other
        }
    }
}

private struct ErrorFixture: Decodable, Sendable {
    let status: Int
    let code: String
    let headers: [ContractItem]
    let body: ErrorBody

    struct ErrorBody: Decodable, Sendable {
        let error: ErrorValue

        struct ErrorValue: Decodable, Sendable {
            let code: String
            let requestId: String
        }
    }
}

private enum ContractJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: Self])
    case array([Self])
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: Self].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    func has(pointer: String) -> Bool {
        guard pointer.hasPrefix("/") else { return false }
        var current = self
        for encodedPart in pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            let part = encodedPart.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            switch current {
            case .object(let object):
                guard let next = object[part] else { return false }
                current = next
            case .array(let array):
                guard let index = Int(part), array.indices.contains(index) else { return false }
                current = array[index]
            default:
                return false
            }
        }
        return true
    }
}
