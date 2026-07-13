import Foundation
import Testing

let expectedNativeOperationIDs: Set<String> = [
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

let expectedMatrixRowIDs: Set<String> = [
    "catalog", "search-index", "book-detail-manifest", "entitlements-paywall",
    "progress-overview", "saved-books", "start-book", "book-state-cursor-preferences",
    "chapter-content", "quiz-load-check-events", "quiz-submit", "ask-the-book",
    "audio-narration-plan", "reading-sessions", "notebook", "fsrs-reviews", "commitments",
    "profile-social", "reading-pairs", "gifts-referrals", "notification-inbox",
    "notification-preferences", "apns-device-registration", "onboarding",
    "apple-purchase-verification", "data-export", "account-deactivation", "account-deletion",
    "mobile-config",
]

let expectedIOSInventoryRevision = "0b0f6bc8399b18e0abd75c0a444af9cf6fe98d40"

let expectedProductionAuthorityTests = [
    "chapter.get": "models.chapter-progress.authority-deletion",
    "quiz.get": "models.quiz-progress.authority-deletion",
    "entitlements.get": "models.entitlement.authority-deletion",
    "own-profile.get": "social.own-profile-identity.authority-deletion",
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
        #expect(evidence.manifestPath == "contracts/native-ios/v1/ios-source-inventory-manifest.json")
        #expect(evidence.iosBaseRevision == manifest.iosBaseRevision)
        #expect(evidence.iosSourceRevision == expectedIOSInventoryRevision)
        #expect(evidence.iosSourceRevisionPhase == "committed_contract_branch")
        #expect(manifest.schemaVersion == "chapterflow-ios-native-inventory-v2")
        #expect(manifest.iosSourceRevision == expectedIOSInventoryRevision)
        #expect(manifest.iosSourceRevisionPhase == "committed_contract_branch")
        #expect(evidence.operationKeySha256 == manifest.operationKeySha256)
        #expect(evidence.producerVariantIdSha256 == manifest.producerVariantIdSha256)
        #expect(evidence.producerIdentitySha256 == manifest.producerIdentitySha256)
        #expect(evidence.relationalRecordCount == manifest.relationalRecordCount)
        #expect(evidence.relationalRecordSha256 == manifest.relationalRecordSha256)
        #expect(evidence.sourceInputTreeSha256 == manifest.sourceInputTreeSha256)
        #expect(evidence.matrixRowCount == manifest.matrixRowCount)
        #expect(evidence.exactFactoryTestedProducerCount == 6)
        #expect(evidence.bundleSuccessDecoderTestedOperationCount == 24)
        #expect(!evidence.backendRuntimeFactoryValidationPerformed)
        #expect(manifest.operationKeyCount == 83)
        #expect(manifest.producerVariantCount == 93)
        #expect(manifest.relationalRecordCount == 93)
        #expect(manifest.records.count == 93)
        #expect(manifest.matrixRowCount == 29)
        #expect(manifest.matrixRows.count == 29)
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

    @Test("blocked operations have closed remediation ownership")
    func blockerResolutions() throws {
        let bundle = try NativeContractBundleFixture.load()
        let blocked = bundle.operations.filter { $0.coverage == "blocked" }

        #expect(blocked.count == 23)
        for operation in blocked {
            let blocker = try #require(operation.blocker)
            try validate(blocker.resolution, operationID: operation.id)
        }
        #expect(bundle.operations.filter { $0.coverage != "blocked" }.allSatisfy { $0.blocker == nil })
    }

    @Test("recent-auth routes do not claim active-user enforcement")
    func recentAuthClassification() throws {
        let bundle = try NativeContractBundleFixture.load()
        let accountDelete = try #require(bundle.operations.first { $0.id == "account-delete.post" })
        let export = try #require(bundle.operations.first { $0.id == "export.get" })

        #expect(accountDelete.auth.authClass == "recent_auth_user")
        #expect(export.auth.authClass == "recent_auth_user")
    }

    @Test("authority proof claims name production consumer tests")
    func authorityProofs() throws {
        let bundle = try NativeContractBundleFixture.load()
        try validateAuthorityProofs(bundle)

        #expect(bundle.authorityProofSummary.structuralFixtureVerifiedOperationCount == 51)
        #expect(bundle.authorityProofSummary.productionConsumerVerifiedOperationCount == 4)
        #expect(bundle.authorityProofSummary.blockedOrUnprovenOperationCount == 1)
        let quizSubmit = try #require(bundle.operations.first { $0.id == "quiz-submit.post" })
        #expect(quizSubmit.authority.proof.level == "blocked_unproven")
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

    @Test("analytics producer reassignment trips the relational canary")
    func analyticsProducerSwapCanary() throws {
        var bundle = try NativeContractBundleFixture.load()
        let trackIndex = try operationIndex("analytics-track.post", in: bundle)
        let beaconIndex = try operationIndex("analytics-beacon.post", in: bundle)
        let trackEvidence = bundle.operations[trackIndex].nativeRequestFixtures[0].producerEvidence
        let beaconEvidence = bundle.operations[beaconIndex].nativeRequestFixtures[0].producerEvidence
        bundle.operations[trackIndex].nativeRequestFixtures[0].producerEvidence = beaconEvidence
        bundle.operations[beaconIndex].nativeRequestFixtures[0].producerEvidence = trackEvidence

        #expect(throws: NativeContractValidationError.self) {
            try validate(bundle)
        }
    }

    @Test("commitment matrix reassignment trips the relational canary")
    func commitmentMatrixMoveCanary() throws {
        var bundle = try NativeContractBundleFixture.load()
        let operationIndex = try operationIndex("commitment.get", in: bundle)
        let commitmentsIndex = try matrixRowIndex("commitments", in: bundle)
        let catalogIndex = try matrixRowIndex("catalog", in: bundle)

        bundle.operations[operationIndex].matrixRowId = "catalog"
        bundle.inventory.matrixRows[commitmentsIndex].operationIds.removeAll {
            $0 == "commitment.get"
        }
        bundle.inventory.matrixRows[catalogIndex].operationIds.append("commitment.get")
        bundle.inventory.matrixRows[catalogIndex].operationIds.sort()

        #expect(throws: NativeContractValidationError.self) {
            try validate(bundle)
        }
    }

    @Test("matrix summary member replacement trips the grouping canary")
    func matrixSummaryMutationCanary() throws {
        var bundle = try NativeContractBundleFixture.load()
        let catalogIndex = try matrixRowIndex("catalog", in: bundle)
        bundle.inventory.matrixRows[catalogIndex].operationIds[0] = "account-delete.post"

        #expect(throws: NativeContractValidationError.self) {
            try validate(bundle)
        }
    }

    @Test("producer duplicate and removal trips the relational canary")
    func duplicateAndRemovalCanary() throws {
        var bundle = try NativeContractBundleFixture.load()
        let catalogIndex = try operationIndex("catalog.get", in: bundle)
        let searchIndex = try operationIndex("search-index.get", in: bundle)
        bundle.operations[catalogIndex].nativeRequestFixtures[0] =
            bundle.operations[searchIndex].nativeRequestFixtures[0]

        #expect(throws: NativeContractValidationError.self) {
            try validate(bundle)
        }
    }

    @Test("method and route mutation trips the relational canary")
    func methodAndRouteCanary() throws {
        var bundle = try NativeContractBundleFixture.load()
        let catalogIndex = try operationIndex("catalog.get", in: bundle)
        bundle.operations[catalogIndex].method = "POST"
        bundle.operations[catalogIndex].routeTemplate = "/book/catalog-mutated"

        #expect(throws: NativeContractValidationError.self) {
            try validate(bundle)
        }
    }

    @Test("producer symbol and source path mutation trips the relational canary")
    func producerIdentityCanary() throws {
        var bundle = try NativeContractBundleFixture.load()
        let catalogIndex = try operationIndex("catalog.get", in: bundle)
        bundle.operations[catalogIndex].nativeRequestFixtures[0].producerEvidence = [
            "getbooks@Packages/Networking/Sources/Networking/Endpoint+Config.swift:10-11",
        ]

        #expect(throws: NativeContractValidationError.self) {
            try validate(bundle)
        }
    }
}

func parseProducerEvidence(
    _ values: [String],
    operationID: String
) throws -> (symbol: String, sourcePath: String) {
    try requireContract(values.count == 1, "\(operationID) producer evidence count")
    let evidence = values[0]
    guard let lineSuffix = evidence.range(
        of: #":[1-9][0-9]*(?:-[1-9][0-9]*)?$"#,
        options: .regularExpression
    ) else {
        throw NativeContractValidationError.invalid("\(operationID) producer evidence line")
    }
    let identity = evidence[..<lineSuffix.lowerBound]
    guard let separator = identity.lastIndex(of: "@") else {
        throw NativeContractValidationError.invalid("\(operationID) producer evidence identity")
    }
    let symbol = String(identity[..<separator])
    let sourcePath = String(identity[identity.index(after: separator)...])
    try requireContract(!symbol.isEmpty, "\(operationID) producer symbol")
    try requireContract(
        sourcePath.range(
            of: #"^Packages/.+/Sources/.+\.swift$"#,
            options: .regularExpression
        ) != nil,
        "\(operationID) producer source path"
    )
    return (symbol, sourcePath)
}

func inferredProducerKind(_ symbol: String) -> String {
    if symbol.hasPrefix("DefaultAnalyticsClient.Path.") {
        return "analytics_path"
    }
    if symbol == "LiveEntitlementRepository.verifyAppleTransaction"
        || symbol == "ScenarioRepository.syncPendingUploads"
    {
        return "direct_endpoint"
    }
    return "endpoint_factory"
}

func stableVariantSuffix(_ symbol: String) -> String {
    symbol.lowercased()
        .replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func validateMatrixRelations(
    _ bundle: NativeContractBundleFixture,
    manifest: IOSSourceInventoryManifest
) throws {
    let derived = deriveMatrixRows(bundle.operations)
    try validateMatrixRows(manifest.matrixRows, label: "manifest")
    try validateMatrixRows(bundle.inventory.matrixRows, label: "bundle")
    try requireContract(manifest.matrixRows == derived, "manifest matrix grouping")
    try requireContract(bundle.inventory.matrixRows == derived, "bundle matrix grouping")
    try requireContract(bundle.inventory.matrixRows == manifest.matrixRows, "matrix summaries")
}

private func validateMatrixRows(_ rows: [MatrixRow], label: String) throws {
    try requireContract(rows.count == 29, "\(label) matrix count")
    try requireContract(Set(rows.map(\.id)).count == rows.count, "\(label) duplicate matrix row")
    for row in rows {
        try requireContract(!row.operationIds.isEmpty, "\(label) empty matrix row \(row.id)")
        try requireContract(
            Set(row.operationIds).count == row.operationIds.count,
            "\(label) duplicate matrix member \(row.id)"
        )
        try requireContract(row.operationIds == row.operationIds.sorted(), "\(label) matrix sort")
    }
    try requireContract(rows.map(\.id) == rows.map(\.id).sorted(), "\(label) row sort")
}

private func deriveMatrixRows(_ operations: [NativeContractBundleFixture.Operation]) -> [MatrixRow] {
    let grouped = Dictionary(grouping: operations.compactMap { operation -> (String, String)? in
        guard let row = operation.matrixRowId else { return nil }
        return (row, operation.id)
    }, by: \.0)
    return grouped.keys.sorted().map { rowID in
        MatrixRow(id: rowID, operationIds: grouped[rowID, default: []].map(\.1).sorted())
    }
}

func validateAuthorityProofs(_ bundle: NativeContractBundleFixture) throws {
    for operation in bundle.operations {
        try validateAuthorityProof(operation)
    }
    let authorityOperations = bundle.operations.filter { $0.authority.classification != "none" }
    let structuralCount = authorityOperations.filter {
        $0.coverage != "blocked"
            && ["structural_fixture_only", "production_consumer_verified"]
                .contains($0.authority.proof.level)
    }.count
    let productionOperations = authorityOperations.filter {
        $0.authority.proof.level == "production_consumer_verified"
    }
    let blockedOperations = authorityOperations.filter {
        $0.authority.proof.level == "blocked_unproven"
    }

    try requireContract(structuralCount == 51, "structural authority count")
    try requireContract(productionOperations.count == 4, "production authority count")
    try requireContract(blockedOperations.count == 1, "blocked authority count")
    try requireContract(
        Set(productionOperations.map(\.id)) == Set(expectedProductionAuthorityTests.keys),
        "production authority operation set"
    )
    try requireContract(blockedOperations.map(\.id) == ["quiz-submit.post"], "blocked authority set")

    let summary = bundle.authorityProofSummary
    try requireContract(
        summary.structuralFixtureVerifiedOperationCount == structuralCount,
        "structural authority summary"
    )
    try requireContract(
        summary.productionConsumerVerifiedOperationCount == productionOperations.count,
        "production authority summary"
    )
    try requireContract(
        summary.blockedOrUnprovenOperationCount == blockedOperations.count,
        "blocked authority summary"
    )
}

func validateAuthorityProof(_ operation: NativeContractBundleFixture.Operation) throws {
    let authority = operation.authority
    let proof = authority.proof
    if authority.classification == "none" {
        try requireContract(authority.failureMode == "not_applicable", "non-authority failure mode")
        try requireContract(authority.expectedRequiredPointers.isEmpty, "non-authority pointers")
        try requireContract(proof.level == "not_applicable", "non-authority proof level")
        try requireContract(proof.structuralEvidence.isEmpty, "non-authority structural proof")
        try requireContract(proof.productionConsumerTestIds.isEmpty, "non-authority test IDs")
        try requireContract(proof.productionConsumerEvidence.isEmpty, "non-authority evidence")
        try requireContract(proof.gaps.isEmpty, "non-authority gaps")
        return
    }

    try requireContract(authority.failureMode == "fail_closed", "\(operation.id) failure mode")
    try requireContract(
        !authority.expectedRequiredPointers.isEmpty,
        "\(operation.id) authority pointers"
    )
    if operation.coverage == "blocked" {
        try requireContract(proof.level == "blocked_unproven", "\(operation.id) blocked proof")
        try requireContract(proof.structuralEvidence.isEmpty, "\(operation.id) blocked structural proof")
        try requireContract(proof.productionConsumerTestIds.isEmpty, "\(operation.id) blocked test IDs")
        try requireContract(
            proof.productionConsumerEvidence.isEmpty,
            "\(operation.id) blocked consumer evidence"
        )
        try requireContract(hasNonEmptyStrings(proof.gaps), "\(operation.id) blocked proof gaps")
        let blocker = try requireValue(operation.blocker, "\(operation.id) blocked authority owner")
        let authorityGap = try requireValue(
            operation.gaps.first { $0.kind == "native_authority_consumer_proof" },
            "\(operation.id) blocked authority gap"
        )
        try requireContract(
            authorityGap.owner == blocker.resolution.owner,
            "\(operation.id) blocked authority gap owner"
        )
        try requireContract(
            authorityGap.dependency == blocker.resolution.dependency,
            "\(operation.id) blocked authority gap dependency"
        )
        return
    }

    try requireContract(
        hasNonEmptyStrings(proof.structuralEvidence),
        "\(operation.id) structural authority evidence"
    )
    if let testID = expectedProductionAuthorityTests[operation.id] {
        try requireContract(
            proof.level == "production_consumer_verified",
            "\(operation.id) production proof level"
        )
        try requireContract(proof.productionConsumerTestIds == [testID], "\(operation.id) test ID")
        try requireContract(
            hasNonEmptyStrings(proof.productionConsumerEvidence),
            "\(operation.id) production evidence"
        )
        try requireContract(proof.gaps.isEmpty, "\(operation.id) production proof gaps")
        try requireContract(
            !operation.gaps.contains { $0.kind == "native_authority_consumer_proof" },
            "\(operation.id) production authority operation gap"
        )
        return
    }

    try requireContract(proof.level == "structural_fixture_only", "\(operation.id) proof level")
    try requireContract(proof.productionConsumerTestIds.isEmpty, "\(operation.id) test IDs")
    try requireContract(proof.productionConsumerEvidence.isEmpty, "\(operation.id) evidence")
    try requireContract(hasNonEmptyStrings(proof.gaps), "\(operation.id) structural proof gaps")
    let authorityGap = try requireValue(
        operation.gaps.first { $0.kind == "native_authority_consumer_proof" },
        "\(operation.id) authority operation gap"
    )
    try requireContract(authorityGap.owner == "ios", "\(operation.id) authority gap owner")
    try requireContract(
        authorityGap.dependency?.isEmpty == false,
        "\(operation.id) authority gap dependency"
    )
}

func validateRecentAuth(_ bundle: NativeContractBundleFixture) throws {
    for operationID in ["account-delete.post", "export.get"] {
        let operation = try requireValue(
            bundle.operations.first { $0.id == operationID },
            "missing \(operationID)"
        )
        try requireContract(operation.auth.authClass == "recent_auth_user", "\(operationID) auth")
    }
}

func validate(
    _ resolution: NativeContractBundleFixture.Operation.Blocker.Resolution,
    operationID: String
) throws {
    let owners: Set<String> = [
        "ios", "backend", "coordinated", "product_or_security_decision",
    ]
    try requireContract(owners.contains(resolution.owner), "\(operationID) blocker owner")
    try requireContract(!resolution.rationale.isEmpty, "\(operationID) blocker rationale")
    try requireContract(!resolution.dependency.isEmpty, "\(operationID) blocker dependency")
    if resolution.decisionRequired {
        try requireContract(
            resolution.owner == "product_or_security_decision",
            "\(operationID) decision owner"
        )
        try requireContract(
            resolution.unresolvedDecision?.isEmpty == false,
            "\(operationID) unresolved decision"
        )
    } else {
        try requireContract(resolution.unresolvedDecision == nil, "\(operationID) closed decision")
    }
}

private func operationIndex(
    _ operationID: String,
    in bundle: NativeContractBundleFixture
) throws -> Int {
    guard let index = bundle.operations.firstIndex(where: { $0.id == operationID }) else {
        throw NativeContractValidationError.invalid("missing operation \(operationID)")
    }
    return index
}

private func matrixRowIndex(
    _ rowID: String,
    in bundle: NativeContractBundleFixture
) throws -> Int {
    guard let index = bundle.inventory.matrixRows.firstIndex(where: { $0.id == rowID }) else {
        throw NativeContractValidationError.invalid("missing matrix row \(rowID)")
    }
    return index
}

private func hasNonEmptyStrings(_ values: [String]) -> Bool {
    !values.isEmpty && values.allSatisfy { !$0.isEmpty }
}

func requireContract(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NativeContractValidationError.invalid(message) }
}
func isLowercaseGitSHA(_ value: String) -> Bool {
    value.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil
}

func isLowercaseSHA256(_ value: String) -> Bool {
    value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
}

func requireValue<Value>(_ value: Value?, _ message: String) throws -> Value {
    guard let value else { throw NativeContractValidationError.invalid(message) }
    return value
}
