import UserNotifications
import RichNotificationCore

/// Notification Service Extension entry point.
///
/// Intercepts pushes whose APNs payload contains `"mutable-content": 1` and:
/// - Downloads + attaches any image referenced in the payload.
/// - Delivers the enriched content, or falls back to the plain notification on
///   timeout / any failure — the alert is never dropped.
///
/// RF4: reads only from the push payload and the App Group container.
///      Never opens the SwiftData store.
final class NotificationServiceExtension: UNNotificationServiceExtension, @unchecked Sendable {

    // Accessed only from the main thread (system guarantee for these callbacks).
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var attachmentTask: Task<Void, Never>?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler

        guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = mutable

        let payload = PushPayloadParser.parse(mutable.userInfo)
        let handler = contentHandler

        attachmentTask = Task {
            if let attachment = await AttachmentBuilder.build(from: payload) {
                mutable.attachments = [attachment]
            }
            // Deliver enriched content (or plain if no image was attached).
            handler(mutable)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Time budget exhausted — cancel image download and deliver whatever we have.
        // We must NEVER drop the alert, so always call the handler.
        attachmentTask?.cancel()
        if let handler = contentHandler, let content = bestAttemptContent {
            handler(content)
        }
    }
}
