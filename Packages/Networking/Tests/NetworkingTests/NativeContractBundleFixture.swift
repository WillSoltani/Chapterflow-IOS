import Foundation

enum NativeContractValidationError: Error {
    case invalid(String)
}

func validate(_ bundle: NativeContractBundleFixture) throws {
    let manifest = try IOSSourceInventoryManifest.load()
    try validateMetadata(bundle)
    try validateInventory(bundle, manifest: manifest)
    try validateAuthorityProofs(bundle)
    try validateRecentAuth(bundle)
    for operation in bundle.operations { try validate(operation) }
}

private func validateMetadata(_ bundle: NativeContractBundleFixture) throws {
    let provenance = bundle.provenance
    try requireContract(
        bundle.schemaVersion == "chapterflow-native-contract-bundle-v1"
            && bundle.contractVersion == "1"
            && provenance.backendRepository == "WillSoltani/ChapterFlow"
            && provenance.generatorVersion == "chapterflow-native-contract-generator-v1",
        "bundle metadata"
    )
    try requireContract(
        provenance.syntheticDataOnly && provenance.deployedRevision == nil
            && !provenance.deployedRevisionVerified,
        "synthetic non-deployed provenance"
    )
    try requireContract(isLowercaseGitSHA(provenance.behaviorSourceRevision), "behavior revision")
    try requireContract(isLowercaseSHA256(provenance.generatorTreeDigest), "generator digest")
    try requireContract(
        [provenance.behaviorSourceTimestamp, provenance.generatedAt]
            .allSatisfy { ISO8601DateFormatter().date(from: $0) != nil },
        "provenance timestamps"
    )
    try requireContract(
        ["committed_backend_branch", "merged_backend"].contains(provenance.sourceRevisionPhase),
        "source revision phase"
    )
    try requireContract(
        provenance.sourceRevision.map(isLowercaseGitSHA) == true,
        "committed source revision"
    )
    let tree = try requireValue(provenance.committedInputTree, "committed input tree")
    try requireContract(
        isLowercaseSHA256(tree.sha256) && tree.inputPathCount > 0
            && tree.expectedMissingPathCount >= 0
            && tree.trustedMainRef == "refs/remotes/origin/main"
            && isLowercaseGitSHA(tree.trustedMainRevision),
        "committed input tree fields"
    )
}

private func validateInventory(
    _ bundle: NativeContractBundleFixture,
    manifest: IOSSourceInventoryManifest
) throws {
    let inventory = bundle.inventory
    try requireContract(
        inventory.uniqueOperationCount == 83 && inventory.nativeProducerCount == 93
            && inventory.matrixRowCount == 29 && bundle.operations.count == 83,
        "inventory counts"
    )
    let operationIDs = bundle.operations.map(\.id)
    let methodRoutes = bundle.operations.map { "\($0.method) \($0.routeTemplate)" }
    try requireContract(
        Set(operationIDs).count == operationIDs.count
            && Set(methodRoutes).count == methodRoutes.count
            && Set(operationIDs) == expectedNativeOperationIDs
            && Set(inventory.matrixRows.map(\.id)) == expectedMatrixRowIDs,
        "inventory membership"
    )
    let requests = bundle.operations.flatMap(\.nativeRequestFixtures)
    let variantIDs = requests.map(\.operationVariantId)
    try requireContract(
        requests.count == 93 && Set(variantIDs).count == variantIDs.count,
        "producer summary"
    )
    let evidence = inventory.iosSourceEvidence
    try requireContract(
        evidence.iosBaseRevision == "92a5c351a42771f546b3d0e575b3b37a8cbfb588"
            && evidence.iosSourceRevision == expectedIOSInventoryRevision
            && evidence.iosSourceRevisionPhase == "committed_contract_branch"
            && evidence.exactFactoryTestedProducerCount == 6
            && evidence.bundleSuccessDecoderTestedOperationCount == 24
            && !evidence.backendRuntimeFactoryValidationPerformed,
        "iOS inventory provenance and limitations"
    )
    try validateManifest(manifest)
    try validateInventoryEvidence(evidence, manifest: manifest)
    try validateProducerRelations(bundle.operations, manifest: manifest)
    try validateMatrixRelations(bundle, manifest: manifest)
}

private func validate(_ operation: NativeContractBundleFixture.Operation) throws {
    try requireContract(
        operation.routeTemplate.hasPrefix("/book/")
            && !operation.nativeRequestFixtures.isEmpty
            && !operation.responseContract.iosModels.isEmpty
            && !operation.responseContract.decoders.isEmpty
            && !operation.ios.factories.isEmpty && !operation.ios.callSites.isEmpty
            && !operation.evidence.isEmpty,
        "\(operation.id) native evidence"
    )
    try validateAuthorityProof(operation)
    if operation.coverage == "blocked" {
        let blocker = try requireValue(operation.blocker, "blocked evidence")
        try validate(blocker.resolution, operationID: operation.id)
        try requireContract(operation.backend == nil && operation.fixtures == nil, "blocked fixtures")
        return
    }
    let backend = try requireValue(operation.backend, "backend evidence")
    let fixtures = try requireValue(operation.fixtures, "fixtures")
    try requireContract(operation.blocker == nil, "covered blocker")
    try requireContract(
        operation.coverage != "full" || !fixtures.errors.isEmpty,
        "documented errors"
    )
    try requireContract(operation.coverage == "full" || !operation.gaps.isEmpty, "partial gaps")
    try requireContract(
        fixtures.request.operationVariantId == fixtures.requestVariants.first?.operationVariantId,
        "primary request variant"
    )
    let canonical = Set(
        operation.nativeRequestFixtures.filter { $0.compatibility == "canonical" }
            .map(\.operationVariantId)
    )
    try requireContract(
        Set(fixtures.requestVariants.map(\.operationVariantId)) == canonical,
        "canonical request variants"
    )
    try requireContract(
        operation.coverage != "full" || backend.serializerProof.kind == "executed_pure_builder",
        "full serializer proof"
    )
    try requireContract(
        Set(fixtures.success.requiredAuthorityFields)
            == Set(operation.authority.expectedRequiredPointers),
        "authority pointers"
    )
    if case .json(let value) = fixtures.success.payload {
        for pointer in fixtures.success.requiredAuthorityFields {
            try requireContract(value.has(pointer: pointer), "authority payload pointer")
        }
    }
    for alias in fixtures.deployedCompatibleSuccessAliases {
        try requireContract(
            !alias.aliasId.isEmpty && !alias.provenance.evidence.isEmpty && !alias.evidence.isEmpty,
            "alias evidence"
        )
    }
    for error in fixtures.errors {
        try requireContract(
            error.code == error.body.error.code
                && error.body.error.requestId.hasPrefix("req_synthetic_"),
            "error envelope"
        )
    }
}

private func validateManifest(_ manifest: IOSSourceInventoryManifest) throws {
    try requireContract(
        manifest.schemaVersion == "chapterflow-ios-native-inventory-v2"
            && manifest.iosRepository == "WillSoltani/Chapterflow-IOS"
            && manifest.iosSourceRevision == expectedIOSInventoryRevision
            && manifest.iosSourceRevisionPhase == "committed_contract_branch",
        "iOS inventory identity and revision"
    )
    try requireContract(
        manifest.operationKeyCount == 83 && manifest.producerVariantCount == 93
            && manifest.relationalRecordCount == 93 && manifest.records.count == 93
            && manifest.matrixRowCount == 29 && manifest.matrixRows.count == 29,
        "iOS inventory counts"
    )
    try requireContract(
        [
            manifest.operationKeySha256, manifest.producerVariantIdSha256,
            manifest.producerIdentitySha256, manifest.relationalRecordSha256,
            manifest.sourceInputTreeSha256,
        ].allSatisfy(isLowercaseSHA256),
        "iOS inventory digests"
    )
    try requireContract(
        Set(manifest.records.map(\.operationId)) == expectedNativeOperationIDs
            && Set(manifest.matrixRows.map(\.id)) == expectedMatrixRowIDs,
        "iOS inventory membership"
    )
    for record in manifest.records {
        try requireContract(
            !record.sourceMethodExpression.isEmpty && !record.sourcePathExpression.isEmpty
                && record.producerKind == inferredProducerKind(record.producerSymbol)
                && record.stableVariantSuffix == stableVariantSuffix(record.producerSymbol)
                && record.operationVariantId
                    == "\(record.operationId):\(record.stableVariantSuffix)",
            "\(record.operationVariantId) manifest relation"
        )
    }
}

private func validateInventoryEvidence(
    _ evidence: NativeContractBundleFixture.Inventory.IOSSourceEvidence,
    manifest: IOSSourceInventoryManifest
) throws {
    try requireContract(
        isLowercaseSHA256(evidence.manifestSha256)
            && evidence.iosRepository == manifest.iosRepository
            && evidence.iosBaseRevision == manifest.iosBaseRevision
            && evidence.iosSourceRevision == manifest.iosSourceRevision
            && evidence.iosSourceRevisionPhase == manifest.iosSourceRevisionPhase,
        "iOS manifest provenance evidence"
    )
    try requireContract(
        evidence.operationKeySha256 == manifest.operationKeySha256
            && evidence.producerVariantIdSha256 == manifest.producerVariantIdSha256
            && evidence.producerIdentitySha256 == manifest.producerIdentitySha256
            && evidence.relationalRecordSha256 == manifest.relationalRecordSha256
            && evidence.sourceInputTreeSha256 == manifest.sourceInputTreeSha256,
        "iOS relational digest evidence"
    )
    try requireContract(
        evidence.relationalRecordCount == manifest.relationalRecordCount
            && evidence.matrixRowCount == manifest.matrixRowCount
            && evidence.exactFactoryTestedProducerCount
                == manifest.exactFactoryTestedProducerCount
            && evidence.bundleSuccessDecoderTestedOperationCount
                == manifest.bundleSuccessDecoderTestedOperationCount
            && !evidence.limitation.isEmpty,
        "iOS relational count evidence"
    )
}

private struct ComparableProducerRelation: Equatable, Sendable {
    let operationId, method, routeTemplate: String
    let matrixRowId: String?
    let operationVariantId, producerKind, producerSymbol, producerSourcePath: String
    let stableVariantSuffix: String
}

private func validateProducerRelations(
    _ operations: [NativeContractBundleFixture.Operation],
    manifest: IOSSourceInventoryManifest
) throws {
    let expected = manifest.records.map {
        ComparableProducerRelation(
            operationId: $0.operationId, method: $0.method, routeTemplate: $0.routeTemplate,
            matrixRowId: $0.matrixRowId, operationVariantId: $0.operationVariantId,
            producerKind: $0.producerKind, producerSymbol: $0.producerSymbol,
            producerSourcePath: $0.producerSourcePath, stableVariantSuffix: $0.stableVariantSuffix
        )
    }
    let actual = try operations.flatMap { operation in
        try operation.nativeRequestFixtures.map { request in
            let producer = try parseProducerEvidence(request.producerEvidence, operationID: operation.id)
            let suffix = stableVariantSuffix(producer.symbol)
            try requireContract(
                request.operationVariantId == "\(operation.id):\(suffix)",
                "\(operation.id) producer variant"
            )
            return ComparableProducerRelation(
                operationId: operation.id, method: operation.method,
                routeTemplate: operation.routeTemplate, matrixRowId: operation.matrixRowId,
                operationVariantId: request.operationVariantId,
                producerKind: inferredProducerKind(producer.symbol), producerSymbol: producer.symbol,
                producerSourcePath: producer.sourcePath, stableVariantSuffix: suffix
            )
        }
    }
    let expectedIDs = expected.map(\.operationVariantId)
    let actualIDs = actual.map(\.operationVariantId)
    try requireContract(
        actual.count == 93 && expected.count == actual.count
            && Set(expectedIDs).count == expectedIDs.count
            && Set(actualIDs).count == actualIDs.count && Set(expectedIDs) == Set(actualIDs),
        "producer relation membership"
    )
    for relation in expected {
        let actualRelation = try requireValue(
            actual.first { $0.operationVariantId == relation.operationVariantId },
            "missing producer relation \(relation.operationVariantId)"
        )
        try validate(actualRelation, equals: relation)
    }
}

private func validate(
    _ actual: ComparableProducerRelation,
    equals expected: ComparableProducerRelation
) throws {
    try requireContract(actual == expected, "\(expected.operationVariantId) producer relation")
}

struct MatrixRow: Decodable, Sendable, Equatable {
    let id: String
    var operationIds: [String]
}

struct NativeContractBundleFixture: Decodable, Sendable {
    let schemaVersion, contractVersion: String
    let provenance: Provenance
    var inventory: Inventory
    let retryAfterPolicy: RetryAfterPolicy
    let authorityProofSummary: AuthorityProofSummary
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
        let backendRepository, behaviorSourceRevision, behaviorSourceTimestamp: String
        let sourceRevisionPhase, generatedAt, generatorVersion, generatorTreeDigest: String
        let sourceRevision: String?
        let committedInputTree: CommittedInputTree?
        let syntheticDataOnly, deployedRevisionVerified: Bool
        let deployedRevision: String?

        struct CommittedInputTree: Decodable, Sendable {
            let sha256, trustedMainRef, trustedMainRevision: String
            let inputPathCount, expectedMissingPathCount: Int
        }
    }

    struct Inventory: Decodable, Sendable {
        let uniqueOperationCount, nativeProducerCount, matrixRowCount: Int
        let iosSourceEvidence: IOSSourceEvidence
        var matrixRows: [MatrixRow]

        struct IOSSourceEvidence: Decodable, Sendable {
            let manifestPath, manifestSha256, iosRepository, iosBaseRevision: String
            let iosSourceRevision: String?
            let iosSourceRevisionPhase, operationKeySha256, producerVariantIdSha256: String
            let producerIdentitySha256, relationalRecordSha256, sourceInputTreeSha256: String
            let relationalRecordCount, matrixRowCount, exactFactoryTestedProducerCount: Int
            let bundleSuccessDecoderTestedOperationCount: Int
            let backendRuntimeFactoryValidationPerformed: Bool
            let limitation: String
        }
    }

    struct RetryAfterPolicy: Decodable, Sendable {
        let implemented: Bool
        let fixtureCount: Int
        let evidence: [String]
        let gap: String
    }

    struct AuthorityProofSummary: Decodable, Sendable {
        let structuralFixtureVerifiedOperationCount, productionConsumerVerifiedOperationCount: Int
        let blockedOrUnprovenOperationCount: Int
    }

    struct Operation: Decodable, Sendable {
        var id: String
        var method, routeTemplate: String
        var matrixRowId: String?
        let auth: Auth
        var nativeRequestFixtures: [Request]
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
            let kind, reason: String
            let owner, dependency: String?
        }

        struct Auth: Decodable, Sendable {
            let authClass: String

            private enum CodingKeys: String, CodingKey {
                case authClass = "class"
            }
        }

        struct ResponseContract: Decodable, Sendable {
            let iosModels, decoders: [String]
        }

        struct Authority: Decodable, Sendable {
            let expectedRequiredPointers: [String]
            let failureMode, classification: String
            let proof: Proof

            struct Proof: Decodable, Sendable {
                let level: String
                let structuralEvidence, productionConsumerTestIds: [String]
                let productionConsumerEvidence, gaps: [String]
            }
        }

        struct IOS: Decodable, Sendable {
            let factories, callSites: [String]
        }

        struct Backend: Decodable, Sendable {
            let serializerProof: SerializerProof

            struct SerializerProof: Decodable, Sendable { let kind: String }
        }

        struct Blocker: Decodable, Sendable {
            let kind: String
            let evidence: [String]
            let expectedRouteSource: String?
            let resolution: Resolution

            struct Resolution: Decodable, Sendable {
                let owner, rationale, dependency: String
                let decisionRequired: Bool
                let unresolvedDecision: String?
            }
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

struct IOSSourceInventoryManifest: Decodable, Sendable {
    let schemaVersion, iosRepository, iosBaseRevision: String
    let iosSourceRevision: String?
    let iosSourceRevisionPhase, operationKeySha256, producerVariantIdSha256: String
    let producerIdentitySha256, relationalRecordSha256, sourceInputTreeSha256: String
    let operationKeyCount, producerVariantCount, matrixRowCount, relationalRecordCount: Int
    let records: [Record]
    let matrixRows: [MatrixRow]
    let exactFactoryTestedProducerCount: Int
    let bundleSuccessDecoderTestedOperationCount: Int

    struct Record: Decodable, Sendable {
        let operationId, method, routeTemplate: String
        let matrixRowId: String?
        let operationVariantId, producerKind, producerSymbol, producerSourcePath: String
        let stableVariantSuffix, sourceMethodExpression, sourcePathExpression: String
    }

    static func load() throws -> Self {
        let url = contractRepositoryRoot()
            .appending(path: "contracts/native-ios/v1/ios-source-inventory-manifest.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

func contractRepositoryRoot() -> URL {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return root
}

struct Request: Decodable, Sendable {
    var operationVariantId: String
    var producerEvidence: [String]
    let queryItems: [ContractItem]
    let body: ContractBody
    let compatibility: String
}

struct ContractBody: Decodable, Sendable {
    let kind: String
    let value: ContractJSONValue?
}

struct ContractItem: Decodable, Sendable, Equatable {
    let name: String
    let value: ContractJSONValue
}

enum ContractPayload: Decodable, Sendable {
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

struct ErrorFixture: Decodable, Sendable {
    let status: Int
    let code: String
    let headers: [ContractItem]
    let body: ErrorBody

    struct ErrorBody: Decodable, Sendable {
        let error: ErrorValue

        struct ErrorValue: Decodable, Sendable {
            let code, requestId: String
        }
    }
}

enum ContractJSONValue: Codable, Sendable, Equatable {
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
