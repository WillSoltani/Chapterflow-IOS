import CryptoKit
import Foundation

/// A privacy-preserving namespace for one authenticated account's entitlement cache.
///
/// The raw Cognito subject is used only while constructing this value. It is not
/// retained or persisted. Only a deterministic SHA-256 digest, namespaced for
/// ChapterFlow entitlement storage, becomes part of the `UserDefaults` cache key.
public struct EntitlementAccountScope: Sendable, Equatable {
    private static let cacheKeyPrefix = "com.chapterflow.entitlement.v2."
    private let digest: String

    /// Creates an opaque cache scope from a stable authenticated subject.
    ///
    /// Returns `nil` for an empty subject so entitlement state fails closed when
    /// the authentication layer cannot provide a stable account identity.
    public init?(authenticatedSubject: String) {
        let subject = authenticatedSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { return nil }

        let input = Data("chapterflow.entitlement.v2\u{0}\(subject)".utf8)
        digest = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    var cacheKey: String {
        Self.cacheKeyPrefix + digest
    }
}
