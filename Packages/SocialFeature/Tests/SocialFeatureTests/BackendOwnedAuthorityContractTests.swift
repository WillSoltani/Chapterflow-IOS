import Foundation
import Models
import Testing
@testable import SocialFeature

@Suite("Backend-owned social authority fixtures")
struct BackendOwnedAuthorityContractTests {
    @Test("production own-profile consumer rejects a deleted identity subject")
    func ownProfileIdentityAuthorityDeletionFailsClosed() throws {
        let operation = try #require(
            try SocialAuthorityContractBundle.load().operation("own-profile.get")
        )
        #expect(operation.authority.failureMode == "fail_closed")
        #expect(operation.authority.expectedRequiredPointers == ["/identity/sub"])
        #expect(operation.authority.proof?.level == "production_consumer_verified")
        #expect(operation.authority.proof?.productionConsumerTestIds == [
            "social.own-profile-identity.authority-deletion",
        ])

        let fixture = try #require(operation.fixtures)
        #expect(fixture.success.payload.kind == "json")
        let canonical = try #require(fixture.success.payload.value)
        let canonicalResponse = try JSONDecoder.chapterFlow.decode(
            OwnProfileResponse.self,
            from: canonical.data()
        )
        #expect(canonicalResponse.profile.userId == "user-synthetic")

        let mutated = try #require(canonical.removing(pointer: "/identity/sub"))
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder.chapterFlow.decode(
                OwnProfileResponse.self,
                from: mutated.data()
            )
        }
    }
}

private struct SocialAuthorityContractBundle: Decodable, Sendable {
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
            let proof: Proof?

            struct Proof: Decodable, Sendable {
                let level: String
                let productionConsumerTestIds: [String]
            }
        }

        struct Fixtures: Decodable, Sendable {
            let success: Success

            struct Success: Decodable, Sendable {
                let payload: SocialContractPayload
            }
        }
    }
}

private struct SocialContractPayload: Decodable, Sendable {
    let kind: String
    let value: SocialContractJSONValue?
}

private enum SocialContractJSONValue: Codable, Sendable, Equatable {
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

    func removing(pointer: String) -> Self? {
        let parts = Self.pointerParts(pointer)
        guard !parts.isEmpty else { return nil }
        return removing(parts: ArraySlice(parts))
    }

    private func removing(parts: ArraySlice<String>) -> Self? {
        guard let head = parts.first else { return nil }
        let tail = parts.dropFirst()
        switch self {
        case .object(var object):
            if tail.isEmpty {
                guard object.removeValue(forKey: head) != nil else { return nil }
            } else {
                guard let child = object[head],
                      let updated = child.removing(parts: tail) else {
                    return nil
                }
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
        default:
            return nil
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
