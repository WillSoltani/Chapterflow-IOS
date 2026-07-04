import Foundation

/// Platform-independent data required to download and save a push notification
/// image as a `UNNotificationAttachment`.
///
/// The actual download (`URLSession`) and `UNNotificationAttachment` creation
/// happen in the extension target, because `UserNotifications` is unavailable
/// on macOS. This type holds only Foundation types so the URL-inference and
/// filename logic can be unit-tested in a macOS package test run.
public struct AttachmentPreparation: Sendable, Equatable {
    /// Remote HTTPS URL to download.
    public let sourceURL: URL
    /// Suggested local filename, including extension (e.g. `"cf-notification-image.jpeg"`).
    public let suggestedFilename: String
    /// UTType identifier hint to pass to `UNNotificationAttachment`.
    /// `nil` when the URL's path extension is unknown or absent.
    public let uniformTypeIdentifier: String?

    /// Returns a preparation for the image URL in `payload`, or `nil` if the
    /// payload carries no image URL.
    public static func prepare(from payload: PushPayload) -> AttachmentPreparation? {
        guard let url = payload.imageURL else { return nil }
        return AttachmentPreparation(sourceURL: url)
    }

    /// Infers filename and UTI from the URL path extension.
    public init(sourceURL: URL) {
        self.sourceURL = sourceURL
        let ext = sourceURL.pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "jpg" : ext
        self.suggestedFilename = "cf-notification-image.\(safeExt)"
        self.uniformTypeIdentifier = Self.uti(for: ext)
    }

    // MARK: - Private

    private static func uti(for ext: String) -> String? {
        switch ext {
        case "jpg", "jpeg": return "public.jpeg"
        case "png":         return "public.png"
        case "gif":         return "com.compuserve.gif"
        case "webp":        return "org.webmproject.webp"
        default:            return nil
        }
    }
}
