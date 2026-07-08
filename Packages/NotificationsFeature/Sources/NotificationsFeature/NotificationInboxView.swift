import SwiftUI
import Models
import DesignSystem
import CoreKit

// MARK: - NotificationInboxView

/// The in-app notification inbox.
///
/// Lists past notifications with unread state. Tapping a row routes the user
/// via the `onOpenURL` callback (deep-link). A "Mark All Read" button posts
/// to the server and clears the unread badge optimistically.
public struct NotificationInboxView: View {

    @State private var model: NotificationInboxModel
    private let onOpenURL: (URL) -> Void

    public init(model: NotificationInboxModel, onOpenURL: @escaping (URL) -> Void) {
        _model = State(initialValue: model)
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Notifications")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .toolbar {
                    if model.unreadCount > 0 {
                        #if os(iOS)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Mark All Read") {
                                Task { await model.markAllRead() }
                            }
                            .font(.cfSubheadline)
                            .accessibilityLabel("Mark all notifications as read")
                        }
                        #else
                        ToolbarItem(placement: .automatic) {
                            Button("Mark All Read") {
                                Task { await model.markAllRead() }
                            }
                            .accessibilityLabel("Mark all notifications as read")
                        }
                        #endif
                    }
                }
        }
        .task { await model.fetch() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.notifications.isEmpty {
            loadingView
        } else if let error = model.error, model.notifications.isEmpty {
            errorView(error)
        } else if model.notifications.isEmpty {
            emptyView
        } else {
            listView
        }
    }

    // MARK: - List

    private var listView: some View {
        List {
            if model.isOffline {
                offlineBanner
            }
            ForEach(model.notifications) { notification in
                NotificationRowView(notification: notification) { url in
                    onOpenURL(url)
                }
                .listRowInsets(EdgeInsets(
                    top: .cfSpacing8,
                    leading: .cfSpacing16,
                    bottom: .cfSpacing8,
                    trailing: .cfSpacing16
                ))
            }
        }
        .listStyle(.plain)
        .refreshable { await model.fetch() }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: .cfSpacing16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading notifications…")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading notifications")
    }

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityHidden(true)
            Text("Couldn't load notifications")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            Text(error.localizedDescription)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.fetch() }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Retry loading notifications")
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityHidden(true)
            Text("No notifications yet")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            Text("Your reading achievements and reminders will appear here.")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No notifications yet")
    }

    private var offlineBanner: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityHidden(true)
            Text("Showing cached notifications — you're offline.")
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .padding(.vertical, .cfSpacing4)
        .listRowBackground(Color.cfSecondaryBackground)
        .accessibilityLabel("You're offline. Showing cached notifications.")
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private func makeModel(
    notifications: [AppNotification] = sampleNotifications,
    unreadCount: Int = 2,
    shouldThrow: Bool = false
) -> NotificationInboxModel {
    let repo = FakeNotificationInboxRepository(
        notifications: notifications,
        unreadCount: unreadCount
    )
    repo.shouldThrow = shouldThrow
    return NotificationInboxModel(repository: repo)
}

private let sampleNotifications: [AppNotification] = [
    AppNotification(
        notificationId: "n1",
        type: .badgeEarned,
        title: "Badge unlocked: Bookworm!",
        body: "You've completed your first book. Keep exploring more titles.",
        isRead: false,
        createdAt: "2024-01-16T10:00:00.000Z",
        deepLink: "chapterflow://profile"
    ),
    AppNotification(
        notificationId: "n2",
        type: .quizUnlocked,
        title: "New quiz available!",
        body: "Chapter 2 of Atomic Habits is ready to quiz. Test your knowledge now.",
        isRead: false,
        createdAt: "2024-01-16T09:00:00.000Z",
        deepLink: "chapterflow://library"
    ),
    AppNotification(
        notificationId: "n3",
        type: .streakReminder,
        title: "Don't break your streak!",
        body: "You're on a 5-day streak. Read something today to keep it going.",
        isRead: true,
        createdAt: "2024-01-15T18:00:00.000Z",
        deepLink: "chapterflow://library"
    ),
    AppNotification(
        notificationId: "n4",
        type: .reviewDue,
        title: "4 cards due for review",
        body: "Your spaced repetition cards are ready.",
        isRead: true,
        createdAt: "2024-01-16T08:00:00.000Z",
        deepLink: "chapterflow://review"
    ),
    AppNotification(
        notificationId: "n5",
        type: .unknown("future_type"),
        title: "Something new happened",
        body: "A future server event — rendered generically so it never crashes.",
        isRead: false,
        createdAt: "2024-01-16T11:00:00.000Z",
        deepLink: nil
    ),
]

#Preview("Inbox — populated (light)") {
    NotificationInboxView(model: makeModel(), onOpenURL: { _ in })
}

#Preview("Inbox — populated (dark)") {
    NotificationInboxView(model: makeModel(), onOpenURL: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Inbox — populated (XXL)") {
    NotificationInboxView(model: makeModel(), onOpenURL: { _ in })
        .dynamicTypeSize(.accessibility3)
}

#Preview("Inbox — empty") {
    NotificationInboxView(model: makeModel(notifications: [], unreadCount: 0), onOpenURL: { _ in })
}

#Preview("Inbox — offline cache") {
    NotificationInboxView(
        model: makeModel(notifications: sampleNotifications, unreadCount: 2),
        onOpenURL: { _ in }
    )
}
#endif
