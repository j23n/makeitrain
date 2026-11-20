import Foundation
import UserNotifications

/// Notifications on this device, as the app model uses them for contract
/// alerts. `SystemNotifications` is the real one; tests and previews have
/// none.
@MainActor
public protocol NotificationProvider: AnyObject {
    /// Asks to show notifications the first time; later calls return what
    /// was decided.
    func requestAuthorization() async -> Bool
    /// Shows a notification at `date`, or now without one, in place of one
    /// waiting under the same id.
    func add(id: String, title: String, body: String, at date: Date?)
    /// Takes back notifications waiting to be shown.
    func remove(ids: [String])
}

/// The system's notifications. They show as banners while the app is in
/// front too, as the Mac's menu bar app always is.
@MainActor
final class SystemNotifications: NSObject, NotificationProvider, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(id: String, title: String, body: String, at date: Date?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = date.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false) }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
    }

    func remove(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
