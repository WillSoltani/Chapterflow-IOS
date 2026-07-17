import Foundation

/// Opaque StoreKit account binding derived only from the authenticated Cognito subject.
///
/// The subject must already be an exact UUID string. No normalization, hashing, or
/// fallback identity is applied, and every textual/reflection surface stays redacted.
public struct StoreKitAccountBinding: Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let appAccountToken: UUID

    public init?(accountID: String) {
        guard let token = UUID(uuidString: accountID),
              token.uuidString.caseInsensitiveCompare(accountID) == .orderedSame else {
            return nil
        }
        appAccountToken = token
    }

    public var description: String { "StoreKitAccountBinding(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["appAccountToken": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// A deterministic description of the StoreKit purchase options that production
/// code converts into `Product.PurchaseOption` values immediately before purchase.
enum StoreKitPurchaseOptionIntent: Sendable, Hashable {
    case appAccountToken(UUID)
    case winBackOffer(String)
}
