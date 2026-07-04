import Foundation
import UserNotifications
import RichNotificationCore

/// Downloads an image from the URL described in a push payload and wraps it in
/// a `UNNotificationAttachment`.
///
/// This type lives in the extension target (not `RichNotificationCore`) because
/// `UNNotificationAttachment` is iOS-only. All URL-parsing and filename logic
/// lives in `AttachmentPreparation` (in `RichNotificationCore`) and is tested
/// separately.
///
/// RF4: uses only the push payload — no SwiftData store access.
enum AttachmentBuilder {

    /// Downloads the image referenced by `payload` and returns a
    /// `UNNotificationAttachment`, or `nil` on any failure (network error,
    /// non-2xx response, write failure). Never throws — callers rely on the
    /// `nil` fallback to deliver the plain notification instead.
    static func build(from payload: PushPayload) async -> UNNotificationAttachment? {
        guard let prep = AttachmentPreparation.prepare(from: payload) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: prep.sourceURL)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode),
                !data.isEmpty
            else { return nil }

            // Write to a uniquely-named temp file to avoid collisions between
            // concurrent extension invocations.
            let ext = prep.sourceURL.pathExtension
            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext.isEmpty ? "jpg" : ext)
            try data.write(to: tmpURL, options: .atomic)

            var options: [String: Any] = [:]
            if let uti = prep.uniformTypeIdentifier {
                options[UNNotificationAttachmentOptionsTypeHintKey] = uti
            }

            return try UNNotificationAttachment(
                identifier: "cf-image-\(UUID().uuidString)",
                url: tmpURL,
                options: options.isEmpty ? nil : options
            )
        } catch {
            return nil
        }
    }
}
