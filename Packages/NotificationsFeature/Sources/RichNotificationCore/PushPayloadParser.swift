import Foundation

/// Parses raw `userInfo` dictionaries from `UNNotificationRequest` into a
/// typed `PushPayload`.
///
/// Extracted from the extension entry point so the logic is unit-testable on
/// macOS, where `UNNotificationServiceExtension` is unavailable.
///
/// Key contract (per docs/ios/PUSH-CONTRACT.md):
/// - `"type"` — push type (string)
/// - `"imageURL"` / `"image_url"` — HTTPS image to download and attach
/// - `"badgeKey"` / `"badge_key"` — badge identifier for badge_earned pushes
/// - `"badgeName"` / `"badge_name"` — human-readable badge name
/// - `"bookId"` / `"book_id"` — book identifier for chapter deep links
/// - `"chapterNumber"` / `"chapter_number"` — chapter number (Int or String)
/// - `"deepLink"` / `"deep_link"` — pre-formed `chapterflow://` URL
public enum PushPayloadParser {

    public static func parse(_ userInfo: [AnyHashable: Any]) -> PushPayload {
        let typeRaw = string(userInfo, keys: "type") ?? ""

        let imageURL: URL? = {
            guard let raw = string(userInfo, keys: "imageURL", "image_url"),
                  let url = URL(string: raw),
                  url.scheme?.lowercased() == "https" else { return nil }
            return url
        }()

        let deepLink: URL? = {
            guard let raw = string(userInfo, keys: "deepLink", "deep_link"),
                  let url = URL(string: raw),
                  url.scheme?.lowercased() == "chapterflow" else { return nil }
            return url
        }()

        return PushPayload(
            typeRaw: typeRaw,
            imageURL: imageURL,
            badgeKey: string(userInfo, keys: "badgeKey", "badge_key"),
            badgeName: string(userInfo, keys: "badgeName", "badge_name"),
            bookId: string(userInfo, keys: "bookId", "book_id"),
            chapterNumber: int(userInfo, keys: "chapterNumber", "chapter_number"),
            deepLink: deepLink
        )
    }

    // MARK: - Private helpers

    private static func string(_ dict: [AnyHashable: Any], keys: String...) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func int(_ dict: [AnyHashable: Any], keys: String...) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int { return value }
            if let str = dict[key] as? String, let value = Int(str) { return value }
        }
        return nil
    }
}
