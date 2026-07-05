import UIKit
import UserNotifications
import UserNotificationsUI
import SwiftUI
import RichNotificationCore

/// Notification Content Extension — custom expanded UI for `CF_BADGE_EARNED` pushes.
///
/// Displays a badge celebration view driven exclusively by the push payload and,
/// optionally, the App Group container snapshot (RF4 — never touches SwiftData).
final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private var hostingController: UIHostingController<BadgeCelebrationView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    func didReceive(_ notification: UNNotification) {
        let payload = PushPayloadParser.parse(notification.request.content.userInfo)

        let celebrationView = BadgeCelebrationView(
            badgeName: payload.badgeName ?? notification.request.content.title,
            badgeKey: payload.badgeKey ?? ""
        )

        if let existing = hostingController {
            existing.rootView = celebrationView
        } else {
            let hosting = UIHostingController(rootView: celebrationView)
            addChild(hosting)
            hosting.view.frame = view.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hosting.view.backgroundColor = .clear
            view.addSubview(hosting.view)
            hosting.didMove(toParent: self)
            hostingController = hosting
        }

        preferredContentSize = CGSize(width: view.bounds.width, height: 260)
    }
}
