import Foundation
import Testing
@testable import Models

struct ModelContractCase: Sendable, CustomTestStringConvertible {
    let operationID: String
    let decodeAndRoundTrip: @Sendable (Data) throws -> Void

    var testDescription: String { operationID }
}

let backendOwnedModelCases: [ModelContractCase] = [
    modelCase("catalog.get", CatalogResponse.self),
    modelCase("search-index.get", SearchIndexResponse.self),
    modelCase("book-detail.get", BookManifest.self),
    modelCase("chapter.get", ChapterResponse.self),
    modelCase("quiz.get", QuizResponse.self),
    modelCase("concept-graph.get", ConceptGraph.self),
    modelCase("journeys.get", JourneysListResponse.self),
    modelCase("seasonal-event.get", ActiveEventResponse.self),
    modelCase("badges.get", BadgesResponse.self),
    modelCase("scenarios.get", ScenariosResponse.self),
    modelCase("book-state.get", BookStateResponse.self),
    modelCase("commitments.get", CommitmentsResponse.self),
    modelCase("dashboard.get", DashboardResponse.self),
    modelCase("entitlements.get", EntitlementResponse.self),
    modelCase("event-progress.get", EventProgressResponse.self),
    modelCase("flow-points.get", FlowPointsResponse.self),
    modelCase("notebook.get", NotebookResponse.self),
    modelCase("notifications.get", NotificationsResponse.self),
    modelCase("progress.get", ProgressOverviewResponse.self),
    modelCase("reviews.get", ReviewsResponse.self),
    modelCase("saved.get", SavedBooksResponse.self),
    modelCase("shop.get", ShopResponse.self),
    modelCase("streak.get", StreakResponse.self),
    modelCase("tier.post", TierResponse.self),
]

@Suite("Backend-owned canonical model fixtures")
struct BackendOwnedContractTests {
    @Test("canonical and deployed-compatible payloads decode and cache round-trip", arguments: backendOwnedModelCases)
    func decodesCanonicalAndAliases(_ contract: ModelContractCase) throws {
        let operation = try #require(try ModelContractBundle.load().operation(contract.operationID))
        let fixtures = try #require(operation.fixtures)

        try contract.decodeAndRoundTrip(try fixtures.success.payload.data())
        for alias in fixtures.deployedCompatibleSuccessAliases {
            try contract.decodeAndRoundTrip(try alias.payload.data())
        }
    }

    @Test("unknown additive root fields do not break canonical payloads", arguments: backendOwnedModelCases)
    func additiveFieldsAreTolerated(_ contract: ModelContractCase) throws {
        let operation = try #require(try ModelContractBundle.load().operation(contract.operationID))
        let fixtures = try #require(operation.fixtures)
        guard let value = fixtures.success.payload.value,
              case .object(var object) = value else {
            return
        }
        object["futureSyntheticField"] = .object(["version": .number(2)])

        try contract.decodeAndRoundTrip(try ModelJSONValue.object(object).data())
    }

    @Test("deleting every declared authority pointer fails the bundle authority gate")
    func authorityPointersFailClosed() throws {
        let bundle = try ModelContractBundle.load()
        let guarded = bundle.operations.filter {
            $0.authority.failureMode == "fail_closed" && $0.fixtures != nil
        }

        #expect(!guarded.isEmpty)
        for operation in guarded {
            let fixture = try #require(operation.fixtures)
            for pointer in operation.authority.expectedRequiredPointers {
                let canonical = try #require(fixture.success.payload.value)
                let mutated = try #require(canonical.removing(pointer: pointer))
                #expect(throws: MissingAuthorityField.self) {
                    try requireAuthority(
                        operation.authority.expectedRequiredPointers,
                        in: mutated
                    )
                }
            }
        }
    }

    @Test("removing each entitlement authority field makes the app decoder reject the fixture")
    func entitlementDecoderFailsClosed() throws {
        let operation = try #require(try ModelContractBundle.load().operation("entitlements.get"))
        let fixture = try #require(operation.fixtures)

        for pointer in operation.authority.expectedRequiredPointers {
            let canonical = try #require(fixture.success.payload.value)
            let mutated = try #require(canonical.removing(pointer: pointer))
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: mutated.data())
            }
        }
    }

    @Test("unknown entitlement plans remain non-Pro")
    func unknownEntitlementPlanFailsClosed() throws {
        let operation = try #require(try ModelContractBundle.load().operation("entitlements.get"))
        let fixture = try #require(operation.fixtures)
        let canonical = try #require(fixture.success.payload.value)
        let mutated = try canonical.replacing(
            pointer: "/entitlement/plan",
            with: .string("FUTURE_SYNTHETIC_PLAN")
        )
        let response = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: mutated.data())

        #expect(response.entitlement.plan == .unknown("FUTURE_SYNTHETIC_PLAN"))
        #expect(!EntitlementEvaluator().isPro(response.entitlement))
    }

    @Test("missing quiz unlock authority defaults to the first chapter")
    func missingQuizUnlockIsConservative() throws {
        let operation = try #require(try ModelContractBundle.load().operation("quiz.get"))
        let fixture = try #require(operation.fixtures)
        let canonical = try #require(fixture.success.payload.value)
        let mutated = try #require(
            canonical.removing(pointer: "/progress/unlockedThroughChapterNumber")
        )

        let response = try JSONDecoder.chapterFlow.decode(QuizResponse.self, from: mutated.data())
        #expect(response.progress.unlockedThroughChapterNumber == 1)
    }

    @Test("catalog drops a malformed cosmetic item without losing valid books")
    func cosmeticCollectionIsLossy() throws {
        let operation = try #require(try ModelContractBundle.load().operation("catalog.get"))
        let fixture = try #require(operation.fixtures)
        guard let value = fixture.success.payload.value,
              case .object(var root) = value,
              case .array(var books) = root["books"] else {
            Issue.record("catalog fixture must contain a books array")
            return
        }
        let validCount = books.count
        books.append(.null)
        root["books"] = .array(books)

        let decoded = try JSONDecoder.chapterFlow.decode(
            CatalogResponse.self,
            from: ModelJSONValue.object(root).data()
        )
        #expect(decoded.books.count == validCount)
    }

    @Test("shared date decoder accepts ISO-8601 with and without fractional seconds")
    func dateVariants() throws {
        struct DateFixture: Decodable { let value: Date }
        let whole = Data(#"{"value":"2026-07-13T12:34:56Z"}"#.utf8)
        let fractional = Data(#"{"value":"2026-07-13T12:34:56.789Z"}"#.utf8)

        let first = try JSONDecoder.chapterFlow.decode(DateFixture.self, from: whole)
        let second = try JSONDecoder.chapterFlow.decode(DateFixture.self, from: fractional)
        #expect(abs(second.value.timeIntervalSince(first.value) - 0.789) < 0.001)
    }
}

private func modelCase<Value: Codable & Sendable>(
    _ operationID: String,
    _ type: Value.Type
) -> ModelContractCase {
    ModelContractCase(operationID: operationID) { data in
        let decoded = try JSONDecoder.chapterFlow.decode(Value.self, from: data)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let cached = try encoder.encode(decoded)
        _ = try JSONDecoder.chapterFlow.decode(Value.self, from: cached)
    }
}

private enum MissingAuthorityField: Error { case pointer(String) }

private func requireAuthority(_ pointers: [String], in value: ModelJSONValue) throws {
    for pointer in pointers where !value.has(pointer: pointer) {
        throw MissingAuthorityField.pointer(pointer)
    }
}

private struct ModelContractBundle: Decodable, Sendable {
    let operations: [Operation]

    func operation(_ id: String) -> Operation? { operations.first { $0.id == id } }

    static func load() throws -> Self {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appending(path: "contracts/native-ios/v1/contract-bundle.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    struct Operation: Decodable, Sendable {
        let id: String
        let authority: Authority
        let fixtures: Fixtures?

        struct Authority: Decodable, Sendable {
            let expectedRequiredPointers: [String]
            let failureMode: String
        }

        struct Fixtures: Decodable, Sendable {
            let success: Success
            let deployedCompatibleSuccessAliases: [Alias]

            struct Success: Decodable, Sendable { let payload: ModelPayload }
            struct Alias: Decodable, Sendable { let payload: ModelPayload }
        }
    }
}

private struct ModelPayload: Decodable, Sendable {
    let kind: String
    let value: ModelJSONValue?

    func data() throws -> Data {
        guard kind == "json", let value else { throw CocoaError(.propertyListReadCorrupt) }
        return try value.data()
    }
}

private enum ModelJSONValue: Codable, Sendable, Equatable {
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

    func data() throws -> Data { try JSONEncoder().encode(self) }

    func has(pointer: String) -> Bool { value(at: pointer) != nil }

    func removing(pointer: String) -> Self? {
        let parts = Self.pointerParts(pointer)
        guard !parts.isEmpty else { return nil }
        return removing(parts: ArraySlice(parts))
    }

    func replacing(pointer: String, with replacement: Self) throws -> Self {
        let parts = Self.pointerParts(pointer)
        guard !parts.isEmpty, let value = replacing(parts: ArraySlice(parts), with: replacement) else {
            throw MissingAuthorityField.pointer(pointer)
        }
        return value
    }

    private func value(at pointer: String) -> Self? {
        let parts = Self.pointerParts(pointer)
        guard !parts.isEmpty else { return nil }
        return value(parts: ArraySlice(parts))
    }

    private func value(parts: ArraySlice<String>) -> Self? {
        guard let head = parts.first else { return self }
        let tail = parts.dropFirst()
        switch self {
        case .object(let object): return object[head]?.value(parts: tail)
        case .array(let array):
            guard let index = Int(head), array.indices.contains(index) else { return nil }
            return array[index].value(parts: tail)
        default: return nil
        }
    }

    private func removing(parts: ArraySlice<String>) -> Self? {
        guard let head = parts.first else { return nil }
        let tail = parts.dropFirst()
        switch self {
        case .object(var object):
            if tail.isEmpty {
                guard object.removeValue(forKey: head) != nil else { return nil }
            } else {
                guard let child = object[head], let updated = child.removing(parts: tail) else { return nil }
                object[head] = updated
            }
            return .object(object)
        case .array(var array):
            guard let index = Int(head), array.indices.contains(index) else { return nil }
            if tail.isEmpty {
                array.remove(at: index)
            } else {
                guard let updated = array[index].removing(parts: tail) else { return nil }
                array[index] = updated
            }
            return .array(array)
        default: return nil
        }
    }

    private func replacing(parts: ArraySlice<String>, with replacement: Self) -> Self? {
        guard let head = parts.first else { return nil }
        let tail = parts.dropFirst()
        switch self {
        case .object(var object):
            guard object[head] != nil else { return nil }
            if tail.isEmpty {
                object[head] = replacement
            } else {
                guard let updated = object[head]?.replacing(parts: tail, with: replacement) else { return nil }
                object[head] = updated
            }
            return .object(object)
        case .array(var array):
            guard let index = Int(head), array.indices.contains(index) else { return nil }
            if tail.isEmpty {
                array[index] = replacement
            } else {
                guard let updated = array[index].replacing(parts: tail, with: replacement) else { return nil }
                array[index] = updated
            }
            return .array(array)
        default: return nil
        }
    }

    private static func pointerParts(_ pointer: String) -> [String] {
        guard pointer.hasPrefix("/") else { return [] }
        return pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
        }
    }
}
